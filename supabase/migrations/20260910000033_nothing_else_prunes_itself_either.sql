-- Retention for the append-only tables, and three indexes that index nothing new.
--
-- …032 fixed the cron log. Auditing the rest turned up the same shape: prod had
-- exactly TWO retention rules in the whole database — signup_rate_limit (hourly,
-- 1 day) and marketing_pageview (daily, 180 days) — and trim_marketing_pageview
-- was the only retention FUNCTION. Everything else append-only grows forever.
--
-- ── One function, not four jobs ───────────────────────────────────────────
-- The policy is the point, so it lives in one readable place and one job calls
-- it. A reader should be able to answer "what do we keep, and for how long?" by
-- reading a single function rather than assembling four cron command strings.
--
-- ── The retentions, and why each is what it is ────────────────────────────
--   roast_smartroast_log     365 days.  A TRIGGER folds each row into the
--     SMARTroast calibration tables on insert; nothing reads the history back
--     (lib/roast/smartroastActions.ts writes it and back-fills session_id, and
--     never selects from it). So after the trigger runs a row is an audit
--     trail, not an input. A year is long enough to answer "why did it fire
--     there" for any roast anyone still remembers. 57 rows/day today.
--   client_telemetry_events   90 days.  Diagnostics. 14/day.
--   server_error_events       90 days.  Feeds /app/dev/errors, which is a
--     "what is breaking NOW" screen. A quarter is generous for that; the value
--     of an error report falls off a cliff once the release that caused it is
--     gone. 1/day today, but this is the one that can spike, which is exactly
--     why it should not be unbounded.
--   staged_shipments          90 days, and only when NOT confirmed.  An
--     abandoned AI invoice holds the model's entire raw response in
--     ai_raw_response (jsonb), and nothing ever cleans one up: the four rows on
--     prod today are from April and three of them are older than this window.
--     'confirmed' is excluded on purpose — that row is the receipt for real
--     inventory and stays. staged_line_items follows via ON DELETE CASCADE.
--
-- Deliberately NOT here, because deleting them cannot be undone and that is the
-- owner's call, not a migration's: the mcr_orders_backup_20260805 /
-- mcr_order_details_backup_20260805 tables (4.9 MB, untouched since August).
--
-- ── The indexes ───────────────────────────────────────────────────────────
-- Three indexes that cost write time on every insert and serve no query the
-- surviving index cannot:
--   idx_roast_log_recipes_log (roast_log_id) is a strict LEFT PREFIX of
--     idx_roast_log_recipes_log_recipe (roast_log_id, recipe_id). The composite
--     already takes 10.4 billion scans to the prefix's 1.39 billion.
--   roast_log_lot_consumption has two EXACT duplicate pairs — same columns,
--     same order, different names, one from the original DDL and one added
--     later. The planner has been splitting scans between them arbitrarily.
-- Dropping an index is reversible in one statement, which is why these are here
-- and the table drops are not.

begin;

create or replace function public.prune_append_only_tables()
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_smartroast bigint;
  v_telemetry  bigint;
  v_errors     bigint;
  v_staged     bigint;
begin
  delete from public.roast_smartroast_log where created_at < now() - interval '365 days';
  get diagnostics v_smartroast = row_count;

  delete from public.client_telemetry_events where created_at < now() - interval '90 days';
  get diagnostics v_telemetry = row_count;

  delete from public.server_error_events where created_at < now() - interval '90 days';
  get diagnostics v_errors = row_count;

  -- A confirmed staged shipment is the receipt for inventory that exists. Only
  -- the abandoned ones age out; staged_line_items cascade.
  delete from public.staged_shipments
   where status is distinct from 'confirmed'
     and coalesce(updated_at, created_at) < now() - interval '90 days';
  get diagnostics v_staged = row_count;

  raise notice 'pruned: smartroast=% telemetry=% errors=% staged_shipments=%',
    v_smartroast, v_telemetry, v_errors, v_staged;
end
$$;

comment on function public.prune_append_only_tables() is
  'Retention for the append-only tables. 365d smartroast telemetry, 90d client/server diagnostics, 90d abandoned AI invoices. Called nightly by cron job prune_append_only_tables.';

revoke all on function public.prune_append_only_tables() from public;

-- ── The redundant indexes ──────────────────────────────────────────────────
drop index if exists public.idx_roast_log_recipes_log;
drop index if exists public.roast_log_lot_consumption_origin_purchase_id_idx;
drop index if exists public.roast_log_lot_consumption_roast_log_id_idx;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron not installed — skipping the retention schedule';
    return;
  end if;
  perform cron.unschedule(jobid) from cron.job where jobname = 'prune_append_only_tables';
  perform cron.schedule('prune_append_only_tables', '40 3 * * *',
                        $cron$SELECT public.prune_append_only_tables()$cron$);
end
$$;

-- Prove the function runs and the indexes are gone. The schedule is asserted
-- the same way …032 asserts its own, including the command, because the command
-- is the half that runs unattended.
do $probe$
declare v_schedule text; v_command text; v_left int;
begin
  perform public.prune_append_only_tables();

  select count(*) into v_left from pg_indexes
   where schemaname='public' and indexname in (
     'idx_roast_log_recipes_log',
     'roast_log_lot_consumption_origin_purchase_id_idx',
     'roast_log_lot_consumption_roast_log_id_idx');
  if v_left <> 0 then
    raise exception '% redundant index(es) still present', v_left;
  end if;

  -- The survivors must still be there, or the drops took the wrong ones.
  if not exists (select 1 from pg_indexes where schemaname='public' and indexname='idx_roast_log_recipes_log_recipe')
     or not exists (select 1 from pg_indexes where schemaname='public' and indexname='idx_rllc_origin_purchase')
     or not exists (select 1 from pg_indexes where schemaname='public' and indexname='idx_rllc_roast_log') then
    raise exception 'a surviving index is missing — the wrong index was dropped';
  end if;

  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron absent — schedule not verified';
    return;
  end if;
  select schedule, command into v_schedule, v_command from cron.job where jobname = 'prune_append_only_tables';
  if v_schedule is distinct from '40 3 * * *' then
    raise exception 'prune_append_only_tables is scheduled "%", expected "40 3 * * *"', coalesce(v_schedule,'(missing)');
  end if;
  if v_command is distinct from 'SELECT public.prune_append_only_tables()' then
    raise exception 'prune_append_only_tables runs "%"', coalesce(v_command,'(missing)');
  end if;
end
$probe$;

commit;
