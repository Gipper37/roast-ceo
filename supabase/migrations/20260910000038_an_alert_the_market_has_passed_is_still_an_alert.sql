-- An alert the market has already passed is still an alert.
--
-- Four "below" triggers sat on MCR's market page looking armed. The C crossed
-- 300¢ on 2026-09-15, the one email Resend owed was swallowed, and the row has
-- read the same ever since — is_active true, last_state 'below', nothing on
-- screen admitting it will not speak again until the price climbs back over
-- 300 and falls through a second time. The owner: "those alerts are useless
-- then. if it won't trigger again."
--
-- The fix is three parts and this migration is the storage for all of them.
--
-- 1. REUSABLE BY NATURE. The crossing semantics stay exactly as built — email
--    on the transition ONTO the trigger side, silence while it stays there,
--    email again on the next fresh crossing. Nothing is ever permanently
--    spent, so no column is needed for that; what was missing was the page
--    saying so. The frontend reads last_state / last_checked_price /
--    last_triggered_at, all of which already exist and are already written
--    every hour, and offers a one-click re-arm. No schema owed.
--
-- 2. COOLDOWN. A price oscillating either side of 300¢ would otherwise mail
--    hourly. cooldown_hours caps it at one email per alert per window
--    (default 24, the owner's "maybe a day time delay"). A crossing inside
--    the window is CONSUMED, not deferred: it is the same crossing the
--    operator was already told about, so last_state advances and no mail goes
--    out. That is deliberately not the same as a FAILED send, which must
--    leave last_state alone so the next tick retries — the distinction lives
--    in the cron, not here, but it is why cooldown is a column and not a
--    reason to suppress the retry.
--
-- 3. PERCENT ALERTS. "also percentage drop in a week/day options." A percent
--    alert compares the live quote against THE CLOSE window_days days
--    back — a plain change over a period, not a drawdown off a rolling high,
--    which is what the owner asked for and is also the only version that can
--    be explained in one line on the page. percent_change is a positive
--    magnitude; direction carries the sign, so 'above' is a rise of at least
--    that much and 'below' a fall of at least that much. Both ship: a rise
--    matters to whoever is about to buy.
--
-- Keeping direction and last_state shared between the two kinds is the point.
-- The cron reduces either kind to the same 'above' | 'below' state and runs
-- ONE crossing detector over it, so percent alerts inherit the re-arm, the
-- seed-on-first-pass and the failed-send retry without a second code path.
--
-- threshold_cents therefore has to give up NOT NULL — a percent alert has no
-- threshold — and a shape CHECK takes over the job that NOT NULL was doing,
-- making the two kinds mutually exclusive rather than merely both-nullable.
--
-- The pre-existing cmarket_alerts_threshold_cents_check (threshold_cents > 0)
-- is left standing and needs no exemption for percent rows: NULL > 0 is NULL,
-- and a CHECK passes on NULL. The probe at the bottom asserts that rather
-- than trusting it.
--
-- No permission work. Every write in cmarket/actions.ts, the new re-arm
-- included, goes through requirePermission('market.alerts_manage'), which
-- 20260901000001 created along with its plan_permissions and role_permissions
-- rows. No new key is being introduced, so there is deliberately nothing to
-- insert here.

begin;

alter table public.cmarket_alerts
  add column if not exists alert_kind     text    not null default 'threshold',
  add column if not exists percent_change numeric,
  add column if not exists window_days    integer,
  add column if not exists cooldown_hours integer not null default 24;

alter table public.cmarket_alerts
  alter column threshold_cents drop not null;

comment on column public.cmarket_alerts.alert_kind is
  'threshold = a price level in cents; percent = a move of percent_change over window_days days. The shape CHECK keeps the two sets of columns from mixing.';
comment on column public.cmarket_alerts.percent_change is
  'A positive magnitude, e.g. 5 for 5%. The sign lives in direction: above = a rise of at least this, below = a fall of at least this.';
comment on column public.cmarket_alerts.window_days is
  'How far back the comparison close is taken from, in days. 1 or 7. The cron resolves that date to the last session at or before it, so a 7-day window means a week ago on the calendar, not seven trading days.';
comment on column public.cmarket_alerts.cooldown_hours is
  'At most one email per alert per this many hours. A crossing inside the window is consumed silently — a flapping price must not mail hourly.';

do $$ begin
  alter table public.cmarket_alerts
    add constraint cmarket_alerts_kind_shape_check check (
      case alert_kind
        when 'threshold' then threshold_cents is not null
                          and percent_change  is null
                          and window_days     is null
        when 'percent'   then percent_change  is not null
                          and percent_change  > 0
                          and window_days     in (1, 7)
                          and threshold_cents is null
        else false
      end
    );
exception when duplicate_object then null; end $$;

-- The ALTER above proves the live rows fit the new shape — a row that did not
-- would have aborted it. What is left to prove is the header's claim about
-- the OLD threshold_cents > 0 check tolerating a percent row's NULL, which is
-- three-valued logic rather than anything this migration wrote, and that the
-- rows that are here came through as threshold alerts.
do $probe$
declare v_threshold int; v_percent int; v_broken int;
begin
  if (null::numeric > 0) is not null then
    raise exception 'NULL > 0 is not NULL here — cmarket_alerts_threshold_cents_check would reject percent rows';
  end if;

  select count(*) filter (where alert_kind = 'threshold'),
         count(*) filter (where alert_kind = 'percent'),
         count(*) filter (where alert_kind = 'threshold' and threshold_cents is null)
    into v_threshold, v_percent, v_broken
    from public.cmarket_alerts;
  if v_broken > 0 then
    raise exception '% threshold alerts lost their threshold_cents', v_broken;
  end if;
  raise notice 'cmarket_alerts: % threshold, % percent', v_threshold, v_percent;
end
$probe$;

commit;

notify pgrst, 'reload schema';
