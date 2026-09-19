-- A standing weekly note needs no threshold.
--
-- Two complaints arrived together. "if it's nudged weekly it shouldn't send 4
-- emails if you have 4 crossings set. it should just send the lowest
-- crossing. and/or we should add a weekly email notification option that just
-- sends an email with the current price update every monday or something."
--
-- The first half — one email per recipient per run, led by the most
-- significant crossing — is entirely a cron-side grouping. Every alert in a
-- group still advances its own last_state because every alert was reported in
-- the digest that went out; nothing about that needs storage, so this
-- migration deliberately adds no column for it.
--
-- The second half does need storage: a third kind of alert that is not a
-- trigger at all. A 'digest' alert has no threshold and no percent — it mails
-- the current C on a chosen weekday whether or not the market did anything,
-- so a roaster who wants a standing Monday check-in gets one without arming a
-- trigger they do not want. schedule_dow carries the weekday, 0 = Sunday
-- through 6 = Saturday, matching the extract(dow …) the cron will compare it
-- against; 1 (Monday) is the sensible default and the frontend offers it, but
-- the column stays null-by-default because the other two kinds must not carry
-- a weekday at all.
--
-- A digest is NOT a crossing, and the consequences of that line run through
-- the whole feature: it must never write last_state (there is no side to be
-- on), and so the crossing detector and its re-arm are untouched by it. What
-- it DOES share is last_triggered_at, re-used as the "last sent" stamp. The
-- cron runs hourly; without that guard a Monday would mail seventeen times.
--
-- Timing is the reason this is a weekday and not a timestamp. The cron ticks
-- in UTC, so "Monday" resolved in UTC reaches a Hawaii roaster on Sunday
-- afternoon. The cron resolves the company's facility time zone and sends
-- when the LOCAL weekday matches and the local hour is at or past 7, falling
-- back to UTC for a company with no facility time zone — late is better than
-- never, and a company with no facility is a company with nothing else for
-- the hour to be wrong about. None of that belongs in the schema; the column
-- is a weekday and the cron owns the clock.
--
-- direction is meaningless for a digest. It stays NOT NULL — nullable
-- direction would force every reader of the crossing path to prove a
-- non-null, and that path is the one place in this table that must stay
-- simple. Instead the column gains a default of 'below' so a digest insert
-- can simply omit it, and the shape CHECK below deliberately does NOT pin the
-- value: constraining it would turn an ignored field into an insert-time
-- failure for any caller that happened to pass 'above'. For a digest row
-- direction is inert, and the column comment says so where the next reader
-- will look.
--
-- 20260910000038 is the migration this amends. Its shape CHECK is a CASE over
-- alert_kind whose else-arm is `false`, which is what enforces the set of
-- allowed kinds — there is no separate enum constraint, so adding 'digest'
-- means replacing that one constraint rather than editing a list somewhere
-- else. It is dropped and re-added here rather than patched, because a CHECK
-- cannot be altered in place, and re-adding it re-validates every live row.
--
-- Still 'market.alerts_manage'. No new permission key, so deliberately no
-- role_permissions or plan_permissions rows.

begin;

alter table public.cmarket_alerts
  add column if not exists schedule_dow smallint;

alter table public.cmarket_alerts
  alter column direction set default 'below';

comment on column public.cmarket_alerts.schedule_dow is
  'Digest alerts only: the weekday to mail on, 0 = Sunday through 6 = Saturday, resolved in the company facility''s local time zone (UTC when it has none). Null for threshold and percent alerts.';
comment on column public.cmarket_alerts.alert_kind is
  'threshold = a price level in cents; percent = a move of percent_change over window_days days; digest = a standing weekly note on schedule_dow that reports the price whether or not anything crossed. The shape CHECK keeps the three sets of columns from mixing.';
comment on column public.cmarket_alerts.direction is
  'Which side of the trigger mails, for threshold and percent alerts. Inert for a digest, which reports the price rather than judging it — digest rows carry the column default and the cron ignores it.';
comment on column public.cmarket_alerts.last_triggered_at is
  'When this alert last mailed. The cooldown window for a crossing; the once-a-week guard for a digest, which the hourly cron would otherwise re-send all day.';

-- Replacing 20260910000038's CASE, not redefining the table's shape from
-- scratch: the threshold and percent arms are that migration's, unchanged
-- except for their new obligation to leave schedule_dow alone.
alter table public.cmarket_alerts
  drop constraint if exists cmarket_alerts_kind_shape_check;

alter table public.cmarket_alerts
  add constraint cmarket_alerts_kind_shape_check check (
    case alert_kind
      when 'threshold' then threshold_cents is not null
                        and percent_change  is null
                        and window_days     is null
                        and schedule_dow    is null
      when 'percent'   then percent_change  is not null
                        and percent_change  > 0
                        and window_days     in (1, 7)
                        and threshold_cents is null
                        and schedule_dow    is null
      when 'digest'    then schedule_dow    is not null
                        and schedule_dow between 0 and 6
                        and threshold_cents is null
                        and percent_change  is null
                        and window_days     is null
      else false
    end
  );

-- The ADD above already re-validated every live row — a threshold alert that
-- had somehow acquired a weekday would have aborted it. What is worth proving
-- beyond that is the new arm itself: that a well-formed digest is accepted and
-- that each way of malforming one is refused, since a shape check that admits
-- a digest with no weekday would hand the cron a row it cannot schedule. The
-- probe writes nothing: the accepting case is unwound by raising a sentinel
-- the block swallows, and every refusing case never lands at all.
do $probe$
declare
  v_accepted boolean := false;
  v_left     integer;
  v_kinds    text;
begin
  begin
    insert into public.cmarket_alerts (company_id, direction, alert_kind, schedule_dow, email)
    values ('__shape_probe__', 'below', 'digest', 1, 'probe@invalid.test');
    v_accepted := true;
    raise exception using errcode = 'P0001', message = '__probe_rollback__';
  exception when others then
    if sqlerrm <> '__probe_rollback__' then raise; end if;
  end;
  if not v_accepted then
    raise exception 'the shape check refused a well-formed digest alert';
  end if;

  begin
    insert into public.cmarket_alerts (company_id, direction, alert_kind, email)
    values ('__shape_probe__', 'below', 'digest', 'probe@invalid.test');
    raise exception 'the shape check accepted a digest alert with no weekday';
  exception when check_violation then null; end;

  begin
    insert into public.cmarket_alerts (company_id, direction, alert_kind, schedule_dow, email)
    values ('__shape_probe__', 'below', 'digest', 7, 'probe@invalid.test');
    raise exception 'the shape check accepted a weekday outside 0..6';
  exception when check_violation then null; end;

  begin
    insert into public.cmarket_alerts (company_id, direction, alert_kind, schedule_dow, threshold_cents, email)
    values ('__shape_probe__', 'below', 'digest', 1, 300, 'probe@invalid.test');
    raise exception 'the shape check accepted a digest carrying a threshold';
  exception when check_violation then null; end;

  begin
    insert into public.cmarket_alerts (company_id, direction, alert_kind, schedule_dow, threshold_cents, email)
    values ('__shape_probe__', 'below', 'threshold', 1, 300, 'probe@invalid.test');
    raise exception 'the shape check accepted a threshold alert carrying a weekday';
  exception when check_violation then null; end;

  select count(*) into v_left
    from public.cmarket_alerts where company_id = '__shape_probe__';
  if v_left <> 0 then
    raise exception 'the shape probe left % row(s) behind', v_left;
  end if;

  select string_agg(alert_kind || '=' || n, ', ' order by alert_kind)
    into v_kinds
    from (select alert_kind, count(*) as n from public.cmarket_alerts group by alert_kind) k;
  raise notice 'cmarket_alerts kinds after the replacement: %', coalesce(v_kinds, 'none');
end
$probe$;

commit;

notify pgrst, 'reload schema';
