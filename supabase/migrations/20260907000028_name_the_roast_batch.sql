-- A packer choosing between four rows that all say "Coffee" is not choosing.
--
-- `roasts_available_to_pack` labelled each batch from the roast log's own
-- snapshot columns and fell back to the literal string 'Coffee'. On real data
-- those snapshots are frequently empty — they are filled by some roast paths and
-- not others — so the bagging screen offered a list of identical rows
-- distinguishable only by weight. That is the same failure as printing an id:
-- the answer is technically present and useless to the person reading it.
--
-- Now it falls back THROUGH the live joins rather than to a placeholder:
-- the recipe's name, then the coffee's origin name, and only then a last-resort
-- label. The origin is appended when it adds something the recipe name does not,
-- because two batches of the same blend on the same day is exactly the case
-- where a packer needs to tell them apart.

begin;

create or replace function public.roasts_available_to_pack(p_company_id text, p_days int default 45)
returns table (
  roast_log_id text,
  roast_date   timestamp,
  coffee       text,
  roasted_lbs  numeric,
  packed_lbs   numeric,
  remaining_lbs numeric,
  roasted_by   text
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
         rs.roasted_by_name
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

revoke all on function public.roasts_available_to_pack(text, int) from public;
grant execute on function public.roasts_available_to_pack(text, int) to authenticated;

commit;
