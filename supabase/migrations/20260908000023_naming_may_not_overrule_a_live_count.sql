-- Naming may only fill in where the arithmetic was lost — never where it holds.
--
-- 20260908000022 made naming automatic, and left it able to do something it must
-- never do. Consider a lot bought at 500 lb, 200 lb of it consumed by roasts
-- whose history predates the anchor, and a count that says the lot is now empty.
-- A LATER roast comes up short. The purchase record still shows 300 lb never
-- accounted for, so the naming pass would happily hand that roast 100 lb from a
-- lot a physical count had just declared empty.
--
-- That is inventing. The distinction that makes naming legitimate is narrow and
-- it has to be enforced, not merely intended:
--
--   BEFORE the group's last count — the anchor wiped the running arithmetic, so
--     what remained on any given day is genuinely unknowable from remaining_lbs.
--     The purchase record is then the best available evidence, and the pounds
--     are not in dispute (the count settled those). Only identity is missing.
--     NAMING IS RIGHT.
--
--   AFTER it — the arithmetic is live and was just recomputed. The replay looked
--     at exactly what was on hand and found nothing. That shortfall is a real
--     finding: coffee was roasted that the system has no record of buying. The
--     remedy is to record the shipment that actually arrived, which adjusts the
--     stock AND fills the trace. NAMING WOULD BE A LIE.
--
-- So the pass is now hard-limited to roasts at or before the anchor, and an
-- origin that has never been counted has no anchor and is therefore never named
-- — nothing has been lost there yet.

begin;

create or replace function public._attribute_unsourced_for_origin(
  p_company_id  text,
  p_facility_id text,
  p_origin_id   text,
  p_not_before  date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_anchor timestamptz;
  v_row    record;
  v_lot    record;
  v_take   numeric;
  v_left   numeric;
  v_named  numeric := 0;
  v_roasts text[] := '{}';
begin
  if p_company_id is null or p_facility_id is null or p_origin_id is null then
    return jsonb_build_object('roasts_repaired', 0, 'lbs_named', 0);
  end if;

  select max(clc.count_at) into v_anchor
    from public.coffee_lot_count clc
    join public.coffee_inventory_purchased cip on cip.origin_purchase_id = clc.origin_purchase_id
   where cip.origin = p_origin_id and cip.facility_id = p_facility_id;

  -- Never counted: nothing has been sealed, so nothing is unknowable, so there
  -- is nothing here for naming to legitimately do.
  if v_anchor is null then
    return jsonb_build_object('roasts_repaired', 0, 'lbs_named', 0);
  end if;

  for v_row in
    select s.roast_log_id, s.origin_id, s.facility_id, s.lbs_unmet, rl.roast_date
      from public.roast_lot_shortfall s
      join public.roast_log rl on rl.roast_log_id = s.roast_log_id
     where s.company_id  = p_company_id
       and s.facility_id = p_facility_id
       and s.origin_id   = p_origin_id
       and s.waived_at is null
       -- 🔴 The boundary. A post-anchor gap is a real finding, not a gap to fill.
       and coalesce(rl.roast_date_utc, rl.roast_date::timestamptz) <= v_anchor
       and (p_not_before is null or rl.roast_date::date >= p_not_before)
     order by rl.roast_date asc
  loop
    v_left := v_row.lbs_unmet;

    for v_lot in
      select cip.origin_purchase_id,
             -- Only pounds the purchase record shows nobody has claimed.
             cip.amount - coalesce((
               select sum(c.lbs_consumed) from public.roast_log_lot_consumption c
                where c.origin_purchase_id = cip.origin_purchase_id), 0) as headroom
        from public.coffee_inventory_purchased cip
        left join public.shipment_received sr on sr.shipment_id = cip.shipment_id
       where cip.facility_id = v_row.facility_id
         and cip.origin = v_row.origin_id
         and coalesce(cip.amount, 0) > 0
         -- It has to have been here. Same availability test the draw uses.
         and coalesce(sr.date_received, cip.created_at::date) <= v_row.roast_date::date
         and coalesce(sr.voided, false) = false
       order by coalesce(sr.date_received, cip.created_at::date) asc, cip.created_at asc
    loop
      exit when v_left <= 0.01;
      if coalesce(v_lot.headroom, 0) <= 0.01 then continue; end if;
      v_take := least(v_lot.headroom, v_left);
      insert into public.roast_log_lot_consumption
        (roast_log_id, origin_purchase_id, lbs_consumed, attribution_only)
      values (v_row.roast_log_id, v_lot.origin_purchase_id, round(v_take, 4), true);
      v_left  := v_left - v_take;
      v_named := v_named + v_take;
    end loop;

    if v_left < v_row.lbs_unmet then
      if not (v_row.roast_log_id = any(v_roasts)) then
        v_roasts := v_roasts || v_row.roast_log_id;
      end if;
      if v_left <= 0.01 then
        delete from public.roast_lot_shortfall
         where roast_log_id = v_row.roast_log_id and origin_id = v_row.origin_id
           and facility_id = v_row.facility_id;
      else
        update public.roast_lot_shortfall set lbs_unmet = round(v_left, 4), as_of = now()
         where roast_log_id = v_row.roast_log_id and origin_id = v_row.origin_id
           and facility_id = v_row.facility_id;
      end if;
    end if;
  end loop;

  if array_length(v_roasts, 1) > 0 then
    perform public.value_roasts_lot_consumption(v_roasts);
  end if;

  return jsonb_build_object(
    'roasts_repaired', coalesce(array_length(v_roasts, 1), 0),
    'lbs_named', round(v_named, 2));
end;
$$;

-- ── Where it hangs ─────────────────────────────────────────────────────────
-- At the END of the replay, not on the receipt and count triggers. One hook
-- instead of three, and — the reason it matters — it can then never run BEFORE
-- the replay it is reacting to. recompute_or_enqueue sends deep origins to the
-- async drain, so hanging this on the triggers would have named lots against a
-- state the replay had not rebuilt yet. Here it is correct on both paths.
--
-- The exists-guard inside attribute_after_stock_event makes this free for the
-- overwhelming majority of replays, which touch an origin with nothing open.
-- Clone the DEPLOYED body into a core function rather than retyping ~250 lines
-- of replay that four callers depend on. pg_get_functiondef guarantees the core
-- is byte-identical to what is running; a hand-copy would only guarantee that it
-- looked right.
do $mig$
declare v_def text;
begin
  if to_regprocedure('public._recompute_origin_lot_consumption_core(text, text)') is null then
    select pg_get_functiondef(oid) into v_def
      from pg_proc where proname = 'recompute_origin_lot_consumption'
       and pronamespace = 'public'::regnamespace;
    if v_def is null then
      raise exception 'recompute_origin_lot_consumption is missing — refusing to wrap nothing.';
    end if;
    v_def := replace(v_def,
      'FUNCTION public.recompute_origin_lot_consumption(',
      'FUNCTION public._recompute_origin_lot_consumption_core(');
    if v_def not like '%_recompute_origin_lot_consumption_core(%' then
      raise exception 'Could not rename the replay body — refusing to guess.';
    end if;
    execute v_def;
  end if;
end
$mig$;

comment on function public._recompute_origin_lot_consumption_core(text, text) is
  'The FIFO replay, unchanged. Cloned verbatim from the deployed recompute_origin_lot_consumption so the wrapper could add the naming pass without touching the replay itself.';

-- ── Where the naming pass hangs ────────────────────────────────────────────
-- At the END of the replay, not on the receipt and count triggers. One hook
-- instead of three, and — the reason it matters — it can then never run BEFORE
-- the replay it is reacting to. recompute_or_enqueue sends deep origins to the
-- async drain, so hanging this on those triggers would have named lots against a
-- state the replay had not rebuilt yet. Here it is correct on both paths, and
-- every existing caller (the count trigger, recompute_or_enqueue, the drain)
-- gets it for free.
--
-- The exists-guard inside attribute_after_stock_event makes this free for the
-- overwhelming majority of replays, which touch an origin with nothing open.
create or replace function public.recompute_origin_lot_consumption(p_origin_id text, p_facility_id text)
returns void
language plpgsql
as $$
declare v_company text;
begin
  perform public._recompute_origin_lot_consumption_core(p_origin_id, p_facility_id);

  select company_id into v_company
    from public.coffee_inventory
   where origin_id = p_origin_id and facility_id = p_facility_id
   limit 1;
  if v_company is not null then
    perform public.attribute_after_stock_event(v_company, p_facility_id, p_origin_id);
  end if;
end;
$$;

commit;
