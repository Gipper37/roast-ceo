-- A bin card says what the batch actually weighed.
--
-- Owner, 2026-10-21: *"the bin card is printing the weight calculated by the
-- retention even when the real weight is input."*
--
-- ── WHAT WAS WRONG, AND WHAT WAS NOT ──────────────────────────────────────
--
-- `create_bin_card` is innocent. It already coalesces
-- `measured_roasted_weight, roasted_weight, charge_weight_lbs` in that order
-- and stamps `lbs_basis` to match. The problem is WHEN it runs: the card is
-- minted at CHARGE, hours before anybody puts the batch on a scale, so
-- `measured_roasted_weight` is null and the card freezes charge x retention.
--
-- Nothing ever looked again. `bin_card_data` read `c.lbs_at_print` straight
-- off the row, and the reprint path in `create_bin_card` returns the existing
-- card before it recomputes anything, so every later copy repeated the
-- estimate. A roastery that weighs every batch -- MCR does -- had a card that
-- was wrong by the retention error on every print after the first.
--
-- ── THE FIX IS ON THE READ, NOT THE WRITE ─────────────────────────────────
--
-- `lbs_at_print` keeps its meaning: what the FIRST printed copy said. That is
-- a record of a piece of paper that physically exists and it must not be
-- rewritten. What changes is the card's live reading: `bin_card_data` now
-- works the weight out from the roast log the same way `create_bin_card`
-- does, and falls back to the snapshot when there is no roast log left to
-- ask.
--
-- Fixing it here rather than in the reprint path means every surface agrees
-- at once -- the popup, a reprint, the roast detail page -- instead of only
-- the one path somebody remembered to patch. And a read stays a read: no
-- write happens because somebody opened a card.
--
-- 🔴 The body below is `pg_get_functiondef` off PROD, 2026-10-21, with the
-- two `lbs` lines changed and nothing else touched. CREATE OR REPLACE rewrites
-- the WHOLE function, so a retyped body silently drops whatever the live one
-- had that I did not remember.

begin;

create or replace function public.bin_card_data(p_bin_card_id text)
returns jsonb
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  select jsonb_build_object(
    'bin_card_id', c.bin_card_id,
    'card_code',   c.card_code,
    'company_id',  c.company_id,
    'coffee',      c.coffee_label,
    'recipe',      c.recipe_label,
    'printed_at',  c.printed_at,
    'printed_by',  c.printed_by_name,
    'voided_at',   c.voided_at,
    'facility',    (select f.facility_name from public.facilities f where f.facility_id = c.facility_id),
    'roast_log_id', c.roast_log_id,
    'roast_date',  rl.roast_date,
    -- The recipe owns the blend type; roast_log's stamped copy is gone.
    'roast_type',  rr.roast_type,
    'roaster',     ru.name,
    -- Who charged it: roast_log first (stamped at charge, so a batch with no
    -- profiler session still names somebody), then the session's own stamp.
    'roasted_by',  coalesce(rl.roasted_by_name, rs.roasted_by_name),
    -- LIVE off the roast log, in the same order create_bin_card uses, because
    -- the card is minted at charge and the scale comes later. c.lbs_at_print
    -- is the fallback and stays what the first copy said.
    'lbs',         coalesce(rl.measured_roasted_weight, rl.roasted_weight,
                            rl.charge_weight_lbs, c.lbs_at_print),
    'lbs_basis',   case
                     when rl.roast_log_id is null then c.lbs_basis
                     when rl.measured_roasted_weight is not null then 'measured'
                     when rl.session_id is not null and coalesce(rl.roasted_weight, 0) > 0 then 'roasted'
                     else 'charge'
                   end,
    'lots', coalesce((
       select jsonb_agg(distinct jsonb_build_object('lot', cip.lot_id, 'coffee', cs.coffee_name))
         from public.roast_log_lot_consumption lc
         join public.coffee_inventory_purchased cip
           on cip.origin_purchase_id = lc.origin_purchase_id
         left join public.coffee_source cs on cs.coffee_source_id = cip.coffee_source_id
        where lc.roast_log_id = c.roast_log_id), '[]'::jsonb))
    from public.bin_card c
    left join public.roast_log rl on rl.roast_log_id = c.roast_log_id
    left join public.roast_recipes rr on rr.recipe_id = rl.recipe_id
    left join public.roaster_units ru on ru.roaster_unit_id = rl.roaster_unit_id
    left join public.roast_sessions rs on rs.session_id = rl.session_id
   where c.bin_card_id = p_bin_card_id
     and c.company_id in (select auth_company_ids());
$function$;

comment on column public.bin_card.lbs_at_print is
  'The weight on the FIRST printed copy, kept as a record of paper that exists. It is NOT what the card reads now: bin_card_data works that out live from the roast log, because the card is minted at charge and the batch is weighed afterwards.';

-- 🔴 Asserts only what this file just wrote. A verify block that asserts what
-- the design forbids rolls back the whole release, and two of mine have.
do $$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'bin_card_data';

  if v_def is null then
    raise exception 'bin_card_data is gone';
  end if;
  if position('rl.measured_roasted_weight' in v_def) = 0 then
    raise exception 'bin_card_data still reads the frozen weight: the measured weight is not in its body';
  end if;
  -- The snapshot must survive as the fallback. Losing it would make a card
  -- whose roast was deleted read as having no weight at all.
  if position('c.lbs_at_print' in v_def) = 0 then
    raise exception 'bin_card_data lost the lbs_at_print fallback';
  end if;
end $$;

commit;
