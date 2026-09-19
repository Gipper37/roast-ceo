-- Blend type belongs to the recipe, not to each roast.
--
-- roast_log carried its own roast_type column, a denormalized copy of
-- roast_recipes.roast_type. It never earned its keep:
--
--   * Only ONE of the two roast-creation paths wrote it. addRoast stamped it
--     from the form; the profiler charge and Load-From-Queue never did. Across
--     all tenants it is NULL on 16,595 rows, holds the pre-split value
--     'Single Origin/Post-Blend' on 1,035 more, and is an empty string on 2.
--     For MCR alone it is NULL on 650 of 1,011 roasts. A field that blank
--     cannot be read for history, and nothing was reading it for anything else.
--
--   * No database object reads it. Every engine that needs the blend type --
--     deduct_one_roast, _roast_affected_origins, calculate_par,
--     calculate_restock_level, trg_recalc_coffee_on_nudge and the rest --
--     resolves it by joining roast_recipes live. (deduct_one_roast's `rl` is a
--     PL/pgSQL record populated from rr.roast_type; it is not this column.)
--     No view or matview depends on it either, so the DROP needs no CASCADE.
--
--   * It has no CHECK constraint, and its DEFAULT is that same illegal
--     'Single Origin/Post-Blend' -- a value roast_recipes_roast_type_check
--     rejects outright.
--
-- Two readers existed, both display-only: bin_card_data() emitted it into the
-- card JSON, and the roast detail page printed it in the title subtitle. Both
-- now take it from the recipe, so a roast created through the profiler finally
-- shows the blend type it always should have instead of a blank.
--
-- Keeping the column would have meant a backfill, and the only thing available
-- to backfill FROM is the current recipe -- which is exactly what the readers
-- now do directly. Worse, making it authoritative would diverge the engines
-- from the readers: the engines re-derive from the live recipe, so a stamped
-- value would make historical replays disagree with the page. Point-in-time
-- recipe history is a real feature if it is ever wanted; it is not this column.

begin;

-- bin_card_data: same shape, roast_type now sourced from the recipe.
create or replace function public.bin_card_data(p_bin_card_id text)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
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
    'lbs',         c.lbs_at_print,
    'lbs_basis',   c.lbs_basis,
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
$$;

revoke all on function public.bin_card_data(text) from public;
grant execute on function public.bin_card_data(text) to authenticated;

alter table public.roast_log drop column roast_type;

commit;
