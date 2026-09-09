-- A roast that could not find its green has to say so.
--
-- _deduct_origin_fifo walks the lots that existed on the roast date and stops
-- when it runs out. That is correct — it must never invent stock. But the
-- residual was thrown away: `p_lbs - v_alloc_total` was never written, never
-- flagged, never queued. roast_log_lot_consumption is the ONLY link from a
-- roasted batch back to a green lot, so a short draw silently breaks the chain
-- a recall walks, and nothing anywhere knows it happened.
--
-- Measured on prod before this migration (Maui Coffee Roasters, all time,
-- attributed per COMPONENT — a blend's gap belongs to the component that ran
-- dry, not to the blend's placeholder group):
--     still repairable   151 short draws   150 roasts    2,485.9 lb
--     already frozen     910 short draws   445 roasts   26,901.7 lb
--
-- ── Why "frozen", and why this migration does NOT touch the freezer ─────────
-- recompute_origin_lot_consumption anchors on MAX(coffee_lot_count.count_at)
-- and only re-derives roasts AFTER it. The weekly lot_anchor_snapshots cron
-- (20260707000007) writes synthetic per-lot checkpoints so replay depth stays
-- bounded — which is the fix for the 12-15s loop-bound replays that used to hang
-- a lot edit and stack one replay per origin inside an operator's save
-- (20260707000003). That fix is load-bearing and STAYS. Refusing to checkpoint
-- an origin that still has unattributed roasts would let depth grow unbounded
-- again and bring the hang straight back.
--
-- The information loss was the bug, not the sealing. So: the shortfall is
-- written down as it happens, and its delete window is the SAME anchor window
-- the consumption delete uses. A pre-anchor shortfall row therefore survives
-- every future replay and every checkpoint by construction, with no change to
-- the cron and no change to replay depth. The window closes; the knowledge does
-- not leave with it.
--
-- ── This table is a DERIVED CACHE ──────────────────────────────────────────
-- Every row is recomputable from (what the roast needed) minus (what its
-- consumption rows attribute). recompute_lot_shortfall_all() rebuilds it from
-- first principles, which is what makes the writer helper safe to expose: a
-- forged or erased row is corrected by the next recompute, so there is nothing
-- to gain by touching it. It may not invent a number, and it does not — it
-- records a subtraction.

begin;

-- ── 1. The ledger ───────────────────────────────────────────────────────────
create table if not exists public.roast_lot_shortfall (
  roast_log_id text not null references public.roast_log(roast_log_id) on delete cascade,
  origin_id    text not null,
  facility_id  text not null,
  company_id   text not null references public.companies(company_id),
  -- Pounds the draw needed and could not find. Always > 0; a satisfied draw
  -- deletes its row rather than storing a zero, so "exists" means "short".
  lbs_unmet    numeric not null check (lbs_unmet > 0),
  -- What it needed in total, kept so a surface can say "12 of 40 lb" without
  -- re-deriving the recipe percentage.
  lbs_needed   numeric,
  as_of        timestamptz not null default now(),
  primary key (roast_log_id, origin_id, facility_id)
);

create index if not exists idx_roast_lot_shortfall_origin
  on public.roast_lot_shortfall (company_id, origin_id, facility_id);
create index if not exists idx_roast_lot_shortfall_company
  on public.roast_lot_shortfall (company_id);

comment on table public.roast_lot_shortfall is
  'Green a charged roast needed and the FIFO draw could not find. A derived cache — recompute_lot_shortfall_all() rebuilds it from consumption vs need. Rows survive the count anchor on purpose: the replay window closes, the knowledge does not.';
comment on column public.roast_lot_shortfall.lbs_unmet is
  'Pounds with no lot behind them. This is the length of the break in the recall chain for this roast on this origin.';

alter table public.roast_lot_shortfall enable row level security;

-- Read-only to tenants; the engine is the only writer (see _record_lot_shortfall).
create policy roast_lot_shortfall_read on public.roast_lot_shortfall
  for select using (company_id in (select auth_company_ids()));

grant select on public.roast_lot_shortfall to authenticated;

-- ── 2. Mark attribution-only consumption ───────────────────────────────────
-- The repair pass (next migration) writes consumption rows for roasts that sit
-- BEFORE the anchor, to restore their trace. Those rows must not read as though
-- they drew stock — the count already owns the physical pounds for that window.
-- Harmless to the arithmetic either way (a pre-anchor row never affects a replay,
-- which re-seeds remaining_lbs from counts), but an auditor is owed the
-- distinction between "this green was deducted" and "this green was identified".
alter table public.roast_log_lot_consumption
  add column if not exists attribution_only boolean not null default false;

comment on column public.roast_log_lot_consumption.attribution_only is
  'True when the row was written to restore a broken trace rather than by a stock deduction. The lot is named; remaining_lbs was never touched.';

-- ── 3. The writer ───────────────────────────────────────────────────────────
-- SECURITY DEFINER because _deduct_origin_fifo runs as the invoking user and the
-- table grants no DML. Idempotent and derived (see the header): the worst a
-- direct caller achieves is a stale row that the next recompute overwrites.
create or replace function public._record_lot_shortfall(
  p_roast_log_id text,
  p_origin_id    text,
  p_facility_id  text,
  p_needed       numeric,
  p_allocated    numeric
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_unmet   numeric := coalesce(p_needed, 0) - coalesce(p_allocated, 0);
  v_company text;
begin
  if p_roast_log_id is null or p_origin_id is null or p_facility_id is null then
    return;
  end if;

  -- Satisfied (or over-drawn): there is nothing to say. Clear any prior claim.
  if v_unmet <= 0.01 then
    delete from public.roast_lot_shortfall
     where roast_log_id = p_roast_log_id
       and origin_id    = p_origin_id
       and facility_id  = p_facility_id;
    return;
  end if;

  select company_id into v_company from public.roast_log where roast_log_id = p_roast_log_id;
  if v_company is null then return; end if;

  insert into public.roast_lot_shortfall as s
    (roast_log_id, origin_id, facility_id, company_id, lbs_unmet, lbs_needed, as_of)
  values (p_roast_log_id, p_origin_id, p_facility_id, v_company,
          round(v_unmet, 4), round(coalesce(p_needed, 0), 4), now())
  on conflict (roast_log_id, origin_id, facility_id) do update
    set lbs_unmet  = excluded.lbs_unmet,
        lbs_needed = excluded.lbs_needed,
        company_id = excluded.company_id,
        as_of      = excluded.as_of;
end;
$$;

comment on function public._record_lot_shortfall(text, text, text, numeric, numeric) is
  'Record (or clear) the green a draw could not find. Called by _deduct_origin_fifo on every draw.';

revoke all on function public._record_lot_shortfall(text, text, text, numeric, numeric) from public;
grant execute on function public._record_lot_shortfall(text, text, text, numeric, numeric) to authenticated;

-- ── 4. The draw now reports what it could not find ─────────────────────────
-- Byte-identical to the deployed body except for the two lines at the end. The
-- loop, the ordering, the date filter and the forced-lot exemption are untouched
-- — this migration changes what the function SAYS, never what it DOES.
create or replace function public._deduct_origin_fifo(
  p_roast_log_id text,
  p_origin_id text,
  p_facility_id text,
  p_lbs numeric,
  p_preferred_source text,
  p_roast_date timestamp without time zone,
  p_force_origin_purchase_id text default null::text,
  p_force_source_id text default null::text
)
returns void
language plpgsql
as $function$
DECLARE
    v_lot record;
    v_alloc_total numeric := 0;
    v_lbs_alloc numeric;
BEGIN
    IF COALESCE(p_lbs, 0) <= 0 THEN RETURN; END IF;
    FOR v_lot IN
        SELECT cip.origin_purchase_id, cip.remaining_lbs
          FROM public.coffee_inventory_purchased cip
          LEFT JOIN public.shipment_received sr ON sr.shipment_id = cip.shipment_id
         WHERE cip.facility_id = p_facility_id
           AND COALESCE(cip.remaining_lbs, 0) > 0
           -- the cited group's lots, PLUS the explicitly-borrowed lot (any group),
           -- PLUS (source-true) every lot of the forced source (any group)
           AND (cip.origin = p_origin_id
                OR cip.origin_purchase_id = p_force_origin_purchase_id
                OR (p_force_source_id IS NOT NULL AND cip.coffee_source_id = p_force_source_id))
           -- existed at roast time — the forced LOT is exempt (deliberate pick);
           -- forced-SOURCE lots are NOT exempt (a source draw still respects
           -- roast-time availability, exactly like an in-group FIFO draw).
           AND (cip.origin_purchase_id = p_force_origin_purchase_id
                OR p_roast_date IS NULL
                OR COALESCE(sr.date_received, cip.created_at::date) <= p_roast_date::date)
         ORDER BY
           -- forced (borrowed) lot first, then the forced source (FIFO within it),
           -- then preferred source, then FIFO
           CASE WHEN cip.origin_purchase_id = p_force_origin_purchase_id THEN 0 ELSE 1 END,
           CASE WHEN p_force_source_id IS NOT NULL
                     AND cip.coffee_source_id = p_force_source_id THEN 0 ELSE 1 END,
           CASE WHEN p_preferred_source IS NOT NULL
                     AND cip.coffee_source_id = p_preferred_source THEN 0 ELSE 1 END,
           COALESCE(sr.date_received, cip.created_at::date) ASC,
           cip.created_at ASC
    LOOP
        IF v_alloc_total >= p_lbs THEN EXIT; END IF;
        v_lbs_alloc := LEAST(v_lot.remaining_lbs, p_lbs - v_alloc_total);
        IF v_lbs_alloc <= 0 THEN CONTINUE; END IF;
        UPDATE public.coffee_inventory_purchased
           SET remaining_lbs = remaining_lbs - v_lbs_alloc
         WHERE origin_purchase_id = v_lot.origin_purchase_id;
        INSERT INTO public.roast_log_lot_consumption (roast_log_id, origin_purchase_id, lbs_consumed)
          VALUES (p_roast_log_id, v_lot.origin_purchase_id, v_lbs_alloc);
        v_alloc_total := v_alloc_total + v_lbs_alloc;
    END LOOP;

    -- What it needed and could not find. Written on EVERY draw, so a draw that
    -- now succeeds clears the claim its earlier self made.
    PERFORM public._record_lot_shortfall(
        p_roast_log_id, p_origin_id, p_facility_id, p_lbs, v_alloc_total);
END;
$function$;

-- ── 5. Rebuild from first principles ───────────────────────────────────────
-- The definition of the table, executable. Mirrors deduct_one_roast's needed-
-- per-origin exactly: a pre-blend needs charge x component percentage on each
-- component group (MAX row per (recipe, coffee_item), like the engine); anything
-- else needs its full charge weight on its own group. Roasts the engine refuses
-- to deduct (the back-date guard) ARE included: the gap is real whatever caused
-- it, and a surface can decide what to show. What it must never do is pretend.
create or replace function public.recompute_lot_shortfall_all(p_company_id text default null)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_n int;
begin
  -- One row per (roast, origin) with what that draw needed and what it got.
  -- The percentage is taken as the MAX row per (recipe, coffee_item), exactly
  -- like deduct_one_roast — a recipe carrying duplicate component rows must not
  -- multiply the need.
  create temporary table _gap on commit drop as
  with need as (
    select rl.roast_log_id, rl.facility_id, rl.company_id,
           case when rr.roast_type = 'Pre-Blend' then rc.coffee_item else rl.origin_id end as origin_id,
           case when rr.roast_type = 'Pre-Blend'
                then rl.charge_weight_lbs * coalesce(rc.percentage, 0)
                else rl.charge_weight_lbs end as needed
      from public.roast_log rl
      left join public.roast_recipes rr on rr.recipe_id = rl.recipe_id
      left join lateral (
        select rc2.coffee_item, max(rc2.percentage) as percentage
          from public.recipe_components rc2
         where rr.roast_type = 'Pre-Blend'
           and rc2.recipe_id = rl.recipe_id
           and coalesce(rc2.percentage, 0) > 0
         group by rc2.coffee_item
      ) rc on true
     where rl."charged?" = true
       and coalesce(rl.charge_weight_lbs, 0) > 0
       and rl.facility_id is not null
       and (p_company_id is null or rl.company_id = p_company_id)
  ), got as (
    select c.roast_log_id, cip.origin as origin_id, sum(c.lbs_consumed) as lbs
      from public.roast_log_lot_consumption c
      join public.coffee_inventory_purchased cip on cip.origin_purchase_id = c.origin_purchase_id
     group by 1, 2
  )
  select n.roast_log_id, n.origin_id, n.facility_id, n.company_id,
         round(n.needed - coalesce(g.lbs, 0), 4) as lbs_unmet,
         round(n.needed, 4) as lbs_needed
    from need n
    left join got g on g.roast_log_id = n.roast_log_id and g.origin_id = n.origin_id
   where n.origin_id is not null
     and coalesce(n.needed, 0) > 0
     and n.needed - coalesce(g.lbs, 0) > 0.01;

  -- Clear claims that no longer hold, then restate the ones that do. Two
  -- statements: deleting and upserting the same table inside one statement is
  -- how ON CONFLICT ends up racing a row it cannot see.
  delete from public.roast_lot_shortfall s
   where (p_company_id is null or s.company_id = p_company_id)
     and not exists (
       select 1 from _gap g
        where g.roast_log_id = s.roast_log_id
          and g.origin_id    = s.origin_id
          and g.facility_id  = s.facility_id);

  insert into public.roast_lot_shortfall as s
    (roast_log_id, origin_id, facility_id, company_id, lbs_unmet, lbs_needed, as_of)
  select roast_log_id, origin_id, facility_id, company_id, lbs_unmet, lbs_needed, now()
    from _gap
  on conflict (roast_log_id, origin_id, facility_id) do update
    set lbs_unmet  = excluded.lbs_unmet,
        lbs_needed = excluded.lbs_needed,
        as_of      = excluded.as_of;

  get diagnostics v_n = row_count;
  drop table _gap;
  return v_n;
end;
$$;

comment on function public.recompute_lot_shortfall_all(text) is
  'Rebuild roast_lot_shortfall from consumption vs need. The table''s definition, executable — which is what makes a forged row pointless.';

revoke all on function public.recompute_lot_shortfall_all(text) from public;

-- ── 6. Seed it ──────────────────────────────────────────────────────────────
-- Set-based, one statement, no loop. Records what is already true; changes no
-- consumption row, no remaining_lbs, no cost, and no anchor.
select public.recompute_lot_shortfall_all(null);

commit;
