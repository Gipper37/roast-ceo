-- Reopening an order must not erase the record of who received the coffee.
--
-- release_line_allocation was a bare DELETE:
--
--     delete from public.pack_run_allocation a
--      using public.order_details od
--      where a.order_detail_id = p_order_detail_id ...
--
-- and orders/actions.ts:121 wires it to a STATUS DROPDOWN — RELEASE_ON is
-- {'Open','Canceled'}. So moving a Delivered order back to Open destroyed the
-- only record that customer X received lot Y. No tombstone, no reason, no
-- actor, no way to know it ever existed.
--
-- 🔴 WHY THAT IS THE WORST ONE IN THIS MODULE. pack_run_allocation is the last
-- link in the identity chain — green lot -> roast -> bag -> ORDER -> customer.
-- recall_report walks it to answer the only question a recall actually asks:
-- who has it. Everything else in food safety is soft-deleted on principle
-- (pack_run.voided_at, recall rows, the correction log), and this one row —
-- the one naming a human being who might be drinking the coffee — was the
-- exception. 21 CFR 117.315 wants these records kept for two years; a hard
-- delete wired to a dropdown cannot honour that.
--
-- ── THE THREE READERS EACH WANT SOMETHING DIFFERENT ─────────────────────────
-- This is the whole design, and getting it wrong in either direction is bad:
--
--   pack_run_remaining        must IGNORE released rows, or the bags never
--                             come back to stock and the shelf reads short
--                             forever.
--   allocate_line_from_stock  must IGNORE them in its "already allocated"
--                             guard, or a line released and re-packed is
--                             refused as a double-draw.
--   recall_report             must KEEP them. A released allocation may be an
--                             order that was delivered and then reopened for an
--                             edit — the customer HAS the coffee. Over-including
--                             a consignee in a recall is safe; missing one is
--                             the thing recalls exist to prevent.
--
-- So the rows stay, the two stock readers filter, and the recall shows them
-- with the release flag and reason attached so a human can judge.

begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. The tombstone.
alter table public.pack_run_allocation
  add column if not exists released_at     timestamptz,
  add column if not exists released_by     text references public.team(team_member_id) on delete restrict,
  add column if not exists release_reason  text;

create index if not exists idx_pack_run_allocation_live
  on public.pack_run_allocation (order_detail_id) where released_at is null;

comment on column public.pack_run_allocation.released_at is
  'Set when the allocation was given back — the order reopened or was cancelled. The ROW IS KEPT: a recall still has to be able to reach a customer who received the coffee before the order was reopened.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Release marks; it no longer deletes.
create or replace function public.release_line_allocation(
  p_order_detail_id text,
  p_reason          text default null
)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count int;
  v_actor record;
begin
  select * into v_actor from public.actor_at();

  update public.pack_run_allocation a
     set released_at    = now(),
         released_by    = v_actor.team_member_id,
         release_reason = coalesce(nullif(trim(p_reason), ''),
                                   'Order reopened or cancelled')
    from public.order_details od
   where a.order_detail_id = p_order_detail_id
     and od.order_detail_id = a.order_detail_id
     and od.company_id in (select auth_company_ids())
     and a.released_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

comment on function public.release_line_allocation(text, text) is
  'Give a line''s bags back to stock. Marks the allocation released rather than deleting it — who received which lot is a food-safety record, and a status dropdown must not be able to erase one.';

revoke all on function public.release_line_allocation(text, text) from public;
grant execute on function public.release_line_allocation(text, text) to authenticated;
-- The 1-arg form the frontend calls today keeps working.
drop function if exists public.release_line_allocation(text);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Stock readers ignore released rows — or the bags never come back.
create or replace view public.pack_run_remaining as
select pr.pack_run_id,
       pr.company_id,
       pr.lot_code,
       pr.product_id,
       pr.product_name_snapshot,
       pr.coffee_prep,
       pr.packed_on,
       pr.best_before,
       pr.location,
       pr.bags                                              as bags_packed,
       coalesce(a.allocated, 0)                             as bags_allocated,
       pr.bags - coalesce(a.allocated, 0)                   as bags_remaining
  from public.pack_run pr
  left join lateral (
    select sum(al.bags) as allocated
      from public.pack_run_allocation al
     where al.pack_run_id = pr.pack_run_id
       and al.released_at is null          -- released bags are back on the shelf
  ) a on true
 where pr.voided_at is null;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. void_pack_run releases rather than deletes, for the same reason.
create or replace function public.void_pack_run(p_pack_run_id text, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_run    record;
  v_actor  record;
  v_alloc  int;
  v_isopen boolean;
begin
  select * into v_run from public.pack_run where pack_run_id = p_pack_run_id for update;
  if v_run.pack_run_id is null or v_run.company_id not in (select auth_company_ids()) then
    raise exception 'That bagging run is not one of yours.' using errcode = 'insufficient_privilege';
  end if;

  v_isopen := v_run.closed_at is null;

  if v_isopen then
    if not public.auth_has_permission('pack.run', v_run.company_id) then
      raise exception 'You do not have permission to record bagging.' using errcode = 'insufficient_privilege';
    end if;
  else
    if not public.auth_has_permission('pack.void', v_run.company_id) then
      raise exception 'Voiding a recorded bagging run needs a supervisor. Ask your roastmaster or manager.'
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  if not v_isopen and coalesce(trim(p_reason), '') = '' then
    raise exception 'Say why this run is being voided. A voided food-safety record without a reason is worse than no record.'
      using errcode = 'invalid_parameter_value';
  end if;

  if v_run.voided_at is not null then
    return jsonb_build_object('pack_run_id', p_pack_run_id, 'already_voided', true);
  end if;

  select * into v_actor from public.actor_at();

  update public.pack_run
     set voided_at   = now(),
         voided_by   = v_actor.team_member_id,
         void_reason = coalesce(nullif(trim(p_reason), ''),
                                case when v_isopen then 'Session abandoned before any bags were recorded' end),
         updated_by  = v_actor.actor_name,
         updated_at  = now()
   where pack_run_id = p_pack_run_id;

  -- Was a DELETE. Same argument as release_line_allocation: the order line must
  -- stop counting these bags as covered, but a customer who already received
  -- them has to stay findable.
  update public.pack_run_allocation
     set released_at    = now(),
         released_by    = v_actor.team_member_id,
         release_reason = 'Bagging run voided'
   where pack_run_id = p_pack_run_id and released_at is null;
  get diagnostics v_alloc = row_count;

  return jsonb_build_object(
    'pack_run_id', p_pack_run_id,
    'lot_code',    v_run.lot_code,
    'was_open',    v_isopen,
    'released_allocations', v_alloc);
end;
$$;

revoke all on function public.void_pack_run(text, text) from public;
grant execute on function public.void_pack_run(text, text) to authenticated;

commit;
