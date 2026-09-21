-- Meter the AI spend before there is any AI spend worth metering.
--
-- STRATA already calls a model in production: app/api/invoice/process
-- parses supplier invoices. Nothing anywhere records that it happened, what
-- it cost, or which tenant caused it. That has been survivable at one call
-- site and stops being survivable the moment an assistant is answering
-- questions all day, because a feature whose cost nobody can see is exactly
-- how a surprise bill arrives.
--
-- So the meter lands BEFORE the feature, not alongside it. When the tutor
-- ships there will already be a month of invoice-parsing data in here to
-- compare against, which is the only way to know whether the new thing is
-- behaving.
--
-- ── Why micro-dollars and not cents ───────────────────────────────────────
--
-- A tutor answer costs roughly $0.003. In cents, rounded, that is zero, and
-- a table of zeroes is worse than no table because it looks like it works.
-- cost_micro_usd is millionths of a dollar: $0.003 stores as 3000. Integer,
-- like every other money column in this schema, because floats do not add
-- up and a cost report that disagrees with the invoice is not a cost report.
--
-- ── Why the cost is stored and not derived ────────────────────────────────
--
-- ai_model_rates holds today's prices so the application computes cost at
-- write time from a row rather than a constant that goes stale silently.
-- The RESULT is written onto the event. A later price change must not
-- rewrite what last month actually cost: the rate table is an input to the
-- calculation, never a join in a report.

begin;

create table if not exists public.ai_model_rates (
  model                       text primary key,
  -- Per million tokens, in micro-dollars. Sonnet 5 at $3/MTok input is
  -- 3000000 here.
  input_micro_usd_per_mtok    bigint not null,
  output_micro_usd_per_mtok   bigint not null,
  -- Cache writes cost more than input and cache reads cost far less. Stored
  -- as basis points of the input rate so a provider change is one update:
  -- 12500 = 1.25x for a 5 minute write, 1000 = 0.1x for a read.
  cache_write_bps             integer not null default 12500,
  cache_read_bps              integer not null default 1000,
  is_current                  boolean not null default true,
  notes                       text,
  updated_at                  timestamptz not null default now(),
  constraint ai_model_rates_positive_chk
    check (input_micro_usd_per_mtok > 0 and output_micro_usd_per_mtok > 0),
  constraint ai_model_rates_bps_chk
    check (cache_write_bps >= 0 and cache_read_bps >= 0)
);

comment on table public.ai_model_rates is
  'Provider prices, per million tokens in micro-dollars. An INPUT to the cost calculation at write time. Never join a report to this: the cost that was actually incurred is stored on the event.';

create table if not exists public.ai_usage_events (
  event_id            uuid primary key default gen_random_uuid(),
  company_id          text not null references public.companies(company_id) on delete cascade,
  -- Null for a background job with no person behind it, such as a cron
  -- parse. Not null for anything a human asked for.
  auth_user_id        uuid,

  -- What asked. 'invoice_parse' today; 'assistant_ask' and 'assistant_data'
  -- when those ship. Deliberately not a CHECK: a new caller must not need a
  -- migration before it can be metered, and an unmetered caller is the
  -- problem this table exists to prevent.
  feature             text not null,
  route_path          text,
  model               text not null,

  input_tokens          integer not null default 0,
  cache_creation_tokens integer not null default 0,
  cache_read_tokens     integer not null default 0,
  output_tokens         integer not null default 0,

  cost_micro_usd      bigint not null default 0,
  latency_ms          integer,

  -- The model declined, or a guard refused before the model was called. A
  -- refusal still costs tokens and still matters: a rising refusal rate is
  -- the earliest signal that the corpus or the tool surface is wrong.
  declined            boolean not null default false,
  decline_reason      text,

  created_at          timestamptz not null default now(),

  constraint ai_usage_events_tokens_chk
    check (input_tokens >= 0 and cache_creation_tokens >= 0
           and cache_read_tokens >= 0 and output_tokens >= 0),
  constraint ai_usage_events_cost_chk check (cost_micro_usd >= 0)
);

comment on table public.ai_usage_events is
  'One row per model call. cost_micro_usd is millionths of a dollar, computed at write time from ai_model_rates and then frozen, so a later price change cannot rewrite what last month cost.';
comment on column public.ai_usage_events.cache_read_tokens is
  'Tokens served from the prompt cache at roughly a tenth of input price. On the assistant this should be the LARGEST of the four counts: if it is near zero the cached prefix is being broken, and the bill is several times what it should be.';

-- The two reads that will exist: this tenant's spend this month, and the
-- platform's spend by feature.
create index if not exists idx_ai_usage_company_month
  on public.ai_usage_events (company_id, created_at desc);
create index if not exists idx_ai_usage_feature_month
  on public.ai_usage_events (feature, created_at desc);

alter table public.ai_usage_events enable row level security;
alter table public.ai_model_rates  enable row level security;

-- A roaster may see their own consumption. They may not write it: every row
-- is written by a server action holding the service role, immediately after
-- the provider call, from the provider's own reported token counts.
drop policy if exists tenant_company_read on public.ai_usage_events;
create policy tenant_company_read on public.ai_usage_events
  for select to authenticated
  using (company_id in (select auth_company_ids()));

-- Prices are not tenant data and not secret, but nothing in the app has any
-- reason to read them from the browser.
drop policy if exists service_only on public.ai_model_rates;
create policy service_only on public.ai_model_rates
  for select to authenticated using (false);

revoke all on public.ai_usage_events from anon;
revoke all on public.ai_model_rates  from anon, authenticated;
grant select on public.ai_usage_events to authenticated;
grant all on public.ai_usage_events, public.ai_model_rates to service_role;

-- Current prices. Sonnet 5 is what the assistant will use and what the
-- invoice parser should move to: it is currently pinned to
-- claude-sonnet-4-20250514, two generations old.
insert into public.ai_model_rates
  (model, input_micro_usd_per_mtok, output_micro_usd_per_mtok, notes)
values
  ('claude-sonnet-5',            3000000, 15000000, 'Assistant and invoice parsing'),
  ('claude-haiku-4-5-20251001',   800000,  4000000, 'Cheap tier, not used in the live assistant path'),
  ('claude-opus-5',             15000000, 75000000, 'Not used in the live path'),
  ('claude-sonnet-4-20250514',   3000000, 15000000, 'Legacy. The invoice parser is pinned here.')
on conflict (model) do update
  set input_micro_usd_per_mtok  = excluded.input_micro_usd_per_mtok,
      output_micro_usd_per_mtok = excluded.output_micro_usd_per_mtok,
      notes                     = excluded.notes,
      updated_at                = now();

do $probe$
declare v_rates int; v_leak int;
begin
  select count(*) into v_rates from public.ai_model_rates where is_current;
  if v_rates < 1 then
    raise exception 'no current model rates, so every cost would be recorded as zero';
  end if;

  -- The table records which tenant caused the spend, so it is tenant data
  -- and must be scoped like tenant data.
  select count(*) into v_leak
    from pg_policy
   where polrelid = 'public.ai_usage_events'::regclass and polcmd = 'r';
  if v_leak = 0 then
    raise exception 'ai_usage_events has no select policy, so no tenant could read their own usage';
  end if;

  if has_table_privilege('anon', 'public.ai_usage_events', 'SELECT') then
    raise exception 'anon can read ai_usage_events';
  end if;
end
$probe$;

commit;
