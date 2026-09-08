-- The bagging screen offered every roast in the building.
--
-- Owner, 2026-09-08, looking at "Record coffee you bagged" with
-- `Analog - 12oz - Retail` selected: *"why is bedrock coming up for roasts for
-- analog bags, is that a recipe that goes in analog product."*
--
-- It is not. `roasts_available_to_pack` filtered on company and date and
-- nothing else, so bagging an Analog product listed three Bedrock batches at
-- the top and the one Analog batch fourth. The link it needed was already
-- there and unused: products.recipe_id and roast_log.recipe_id both point at
-- roast_recipes, so a variant knows exactly which roast belongs in it.
--
-- 🔴 This is a traceability defect, not a papercut. The roast a pack run cites
-- IS the identity chain — it is what the recall report walks and what a Costco
-- auditor reads back. Making the wrong batch the easiest thing to tick puts
-- Bedrock coffee under an Analog lot code, which is the mislabelling 21 CFR 7
-- exists to recall.
--
-- WHAT THIS DOES: returns recipe_id on each row so the caller can match. It
-- does NOT refuse the non-matching ones — 403 of 696 products carry no recipe
-- at all (consumables, merch, coffee nobody linked up), and a roaster bagging
-- a house blend into an unlabelled bag is doing something legitimate. The
-- screen defaults to the roasts that match and offers the rest behind a plain
-- "show the others" — a choice, not a block.

begin;

-- The return type gains a column, so the old signature has to go first.
drop function if exists public.roasts_available_to_pack(text, int);

create or replace function public.roasts_available_to_pack(p_company_id text, p_days int default 45)
returns table (
  roast_log_id text,
  roast_date   timestamp,
  coffee       text,
  roasted_lbs  numeric,
  packed_lbs   numeric,
  remaining_lbs numeric,
  roasted_by   text,
  recipe_id    text
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select rl.roast_log_id,
         rl.roast_date,
         coalesce(
           nullif(rl.recipe_name_snapshot, ''),
           rr.recipe_name,
           nullif(rl.coffee_name_snapshot, ''),
           ci.origin,
           'Roast batch'),
         coalesce(rl.measured_roasted_weight, rl.roasted_weight, 0)::numeric,
         coalesce(p.packed, 0)::numeric,
         (coalesce(rl.measured_roasted_weight, rl.roasted_weight, 0) - coalesce(p.packed, 0))::numeric,
         rs.roasted_by_name,
         rl.recipe_id
    from public.roast_log rl
    left join public.roast_recipes rr on rr.recipe_id = rl.recipe_id
    left join public.coffee_inventory ci on ci.origin_id = rl.origin_id
    left join lateral (
      select sum(s.lbs_used) as packed
        from public.pack_run_source s
        join public.pack_run pr on pr.pack_run_id = s.pack_run_id
       where s.roast_log_id = rl.roast_log_id and pr.voided_at is null
    ) p on true
    left join public.roast_sessions rs on rs.session_id = rl.session_id
   where rl.company_id = p_company_id
     and rl.company_id in (select auth_company_ids())
     and rl.roast_date >= (current_date - p_days)
   order by rl.roast_date desc;
$$;

comment on function public.roasts_available_to_pack(text, int) is
  'Roasted weight minus what pack runs have already claimed, with the recipe each batch was roasted from so the bagging screen can put the matching roasts first. The packer should never have to remember which batches they have already bagged, nor scan past three of the wrong coffee to find the right one.';

revoke all on function public.roasts_available_to_pack(text, int) from public;
grant execute on function public.roasts_available_to_pack(text, int) to authenticated;

commit;
