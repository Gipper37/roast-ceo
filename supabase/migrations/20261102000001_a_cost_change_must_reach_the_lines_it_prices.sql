-- A cost change must reach the lines it prices.
--
-- `order_details.unit_cost_at_sale` is SNAPSHOTTED at write time, by
-- handle_order_detail_logic:
--     NEW.unit_cost_at_sale := COALESCE(NEW.quantity,0) * COALESCE(p.total_unit_cogs,0)
-- `products.total_unit_cogs` is itself maintained (update_product_total_cogs on
-- `products`, propagate_consumable_bom_to_product on `product_consumables`), so
-- the column is not stale by neglect. What was missing is the step back out:
-- NOTHING carried a change in it to order lines already written.
--
-- Measured on production 2026-11-01, MCR alone, open books only:
--     already-costed lines                                   2,806
--     stored value disagrees with the recomputed one          1,795   (64%)
--     net recomputed-minus-stored                      -$100,463.27
--     lines with no cost at all that could be priced          1,865
-- The costing itself was never at fault: over those 2,806 lines the bulk
-- `product_cogs_for_keys` and the old scalar `get_product_cogs_on_date`
-- disagreed on ZERO rows, $0.00 -- so this is a propagation defect, not a
-- costing defect. MCR was repaired by hand the same day (+$116,260.10 over
-- 3,660 lines); without this wiring it simply starts drifting again at the
-- ~2.9%/month it was drifting at before.
--
-- WHY A QUEUE AND NOT AN INLINE RE-COST. The worst single product app-wide has
-- 818 open lines, about 0.6 s, which inline would be fine. But
-- propagate_consumable_bom_to_product fires per `product_consumables` row and
-- updates many products at once, and ALL open lines app-wide are 29,446 -- some
-- 21 s of re-costing inside a user's transaction while holding locks on
-- order_details. That is precisely the shape that locked tenants out for 17
-- seconds when charging a roast. So this copies the two siblings that already
-- solve it rather than inventing a third pattern:
--     lot_recompute_queue  + drain_lot_recompute_queue   (cron, every minute)
--     roast_plan_touch     + roast_plan_drain(10)        (cron, every minute)
--
-- THE FREEZE LINE IS `books_closed_through`, NOT posted/invoiced status.
-- guard_posted_order_detail_immutable deliberately omits unit_cost_at_sale from
-- the columns it locks (it guards quantity, product_id, total_price,
-- list_price_total, the discount fields and amount_override): the customer's
-- invoice is price, COGS is a management figure. drain_lot_recompute_queue
-- already says the same thing in its own comment -- "any order line in the
-- replay window (invoiced or not) gets its COGS refreshed ... Invoice totals are
-- price-based and unaffected."
--
-- THE COFFEE SIDE DELIBERATELY GETS NOTHING HERE. It is already covered three
-- ways: save_shipment_lines and propagate_coffee_purchase_to_orders call
-- propagate_coffee_cost_for_shipment_origin on the write path; the per-minute
-- drain calls propagate_origin_cogs_window; and enqueue_inconsistent_origins
-- sweeps nightly for drifted origins. Both coffee propagators already pass an id
-- ARRAY to recost_order_details in a single call, so they inherited the
-- 20261101000003 one-statement rebuild for free. Adding a coffee trigger here
-- would be redundant wiring on an already-covered path.
--
-- NO DML IN THIS MIGRATION. Existing drift in other tenants is deliberately NOT
-- enqueued: that would fire a cascade from a migration, which is how the 2026-10
-- production batch hit the 120 s statement timeout. Any other tenant's repair is
-- a separate, scripted, one-row-per-transaction job.

begin;

-- ---------------------------------------------------------------------------
-- the queue
-- ---------------------------------------------------------------------------

create table if not exists public.product_cogs_recompute_queue (
    id            bigint      generated always as identity primary key,
    company_id    text        not null,
    product_id    text        not null,
    reason        text,
    requested_at  timestamptz not null default now(),
    scheduled_at  timestamptz not null default (now() + interval '5 seconds'),
    status        text        not null default 'pending',
    attempts      integer     not null default 0,
    last_error    text
);

comment on table public.product_cogs_recompute_queue is
  'Products whose total_unit_cogs changed and whose OPEN order lines therefore '
  'need their snapshotted unit_cost_at_sale rebuilt. Drained by '
  'drain_product_cogs_queue every minute. Shaped on lot_recompute_queue.';

-- One pending row per product is enough, which is what makes the DO NOTHING in
-- enqueue_product_cogs_recompute correct.
create unique index if not exists product_cogs_recompute_queue_pending_uq
    on public.product_cogs_recompute_queue (company_id, product_id)
 where status = 'pending';

create index if not exists product_cogs_recompute_queue_pick_idx
    on public.product_cogs_recompute_queue (scheduled_at)
 where status = 'pending';

alter table public.product_cogs_recompute_queue enable row level security;

-- Same tenancy predicate as lot_recompute_queue, verbatim.
drop policy if exists tenant_company_access on public.product_cogs_recompute_queue;
create policy tenant_company_access on public.product_cogs_recompute_queue
    for all
    using      (company_id in (select auth_company_ids()))
    with check (company_id in (select auth_company_ids()));

-- `revoke from public, anon` does NOT revoke from authenticated; be explicit.
revoke all on table public.product_cogs_recompute_queue from public, anon;
grant select, insert, update, delete, references
   on table public.product_cogs_recompute_queue to authenticated;
grant all on table public.product_cogs_recompute_queue to service_role;

-- ---------------------------------------------------------------------------
-- enqueue
-- ---------------------------------------------------------------------------

create or replace function public.enqueue_product_cogs_recompute(
    p_company text, p_product text, p_reason text)
returns void
language plpgsql
as $function$
begin
    -- A product with no company is already orphaned data; the sibling
    -- enqueue_lot_recompute skips on the same grounds.
    if p_company is null or p_product is null then return; end if;

    -- DO NOTHING, not a debounce UPDATE: a re-cost is an absolute rebuild of the
    -- line from current inputs, so an existing pending row already covers this
    -- edit -- and not updating means we never block on a row the drainer holds.
    -- Reasoning taken from enqueue_lot_recompute.
    insert into public.product_cogs_recompute_queue (company_id, product_id, reason)
    values (p_company, p_product, p_reason)
    on conflict (company_id, product_id) where status = 'pending' do nothing;
end;
$function$;

comment on function public.enqueue_product_cogs_recompute(text, text, text) is
  'Mark one product for an open-line COGS rebuild. Idempotent while pending.';

revoke all on function public.enqueue_product_cogs_recompute(text, text, text) from public, anon;
grant execute on function public.enqueue_product_cogs_recompute(text, text, text)
   to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- the trigger: signal only
-- ---------------------------------------------------------------------------

create or replace function public.product_cogs_touch()
returns trigger
language plpgsql
as $function$
begin
    perform public.enqueue_product_cogs_recompute(
        new.company_id, new.product_id, 'total_unit_cogs changed');
    return null;
end;
$function$;

comment on function public.product_cogs_touch() is
  'AFTER UPDATE OF total_unit_cogs on products: enqueue, never re-cost inline.';

revoke all on function public.product_cogs_touch() from public, anon;

drop trigger if exists trg_product_cogs_touch on public.products;
create trigger trg_product_cogs_touch
    after update of total_unit_cogs on public.products
    for each row
    when (old.total_unit_cogs is distinct from new.total_unit_cogs)
    execute function public.product_cogs_touch();

-- ---------------------------------------------------------------------------
-- the drainer
-- ---------------------------------------------------------------------------

create or replace procedure public.drain_product_cogs_queue(p_max integer default 10)
language plpgsql
as $procedure$
declare
    r      record;
    v_ids  text[];
begin
    -- Only one drainer at a time (pg_cron does not serialize same-job runs).
    if not pg_try_advisory_lock(hashtext('product_cogs_drainer'), 0) then return; end if;
    perform set_config('lock_timeout', '10s', false);
    perform set_config('statement_timeout', '60s', false);

    for i in 1..p_max loop
        select id, company_id, product_id into r
          from public.product_cogs_recompute_queue
         where status = 'pending' and scheduled_at <= now()
         order by scheduled_at asc
         for update skip locked
         limit 1;
        exit when not found;

        begin
            -- OPEN lines only. books_closed_through is the freeze line; posted
            -- invoices are included on purpose, because their COGS may move
            -- while their price may not.
            select array_agg(od.order_detail_id::text)
              into v_ids
              from public.order_details od
              join public.companies cmp on cmp.company_id = od.company_id
             where od.product_id  = r.product_id
               and od.company_id = r.company_id
               and coalesce(od.quantity, 0) > 0
               and od.order_date > coalesce(cmp.books_closed_through, '-infinity'::date);

            -- NOTE the stored column is a SIGNAL, never the value.
            -- recost_order_details recomputes from product_cogs_for_keys, so a
            -- total_unit_cogs that is itself wrong (or NULL) cannot propagate a
            -- wrong figure through here. It also skips null/<=0 cogs and writes
            -- only rows whose value actually differs.
            if v_ids is not null then
                perform public.recost_order_details(v_ids);
            end if;

            delete from public.product_cogs_recompute_queue where id = r.id;
        exception when others then
            update public.product_cogs_recompute_queue
               set attempts     = attempts + 1,
                   last_error   = sqlerrm,
                   status       = case when attempts + 1 >= 3 then 'failed' else 'pending' end,
                   scheduled_at = now() + interval '60 seconds'
             where id = r.id;
        end;
        commit;
    end loop;

    perform pg_advisory_unlock(hashtext('product_cogs_drainer'), 0);
end;
$procedure$;

comment on procedure public.drain_product_cogs_queue(integer) is
  'Rebuild snapshotted COGS on the open order lines of queued products. '
  'One product per transaction, 3 attempts then ''failed''.';

revoke all on procedure public.drain_product_cogs_queue(integer) from public, anon, authenticated;
grant execute on procedure public.drain_product_cogs_queue(integer) to service_role;

-- ---------------------------------------------------------------------------
-- verify
-- ---------------------------------------------------------------------------

do $$
declare
    v_tgoid oid;
begin
    if to_regclass('public.product_cogs_recompute_queue') is null then
        raise exception 'queue table was not created';
    end if;

    select t.oid into v_tgoid
      from pg_trigger t
      join pg_class c on c.oid = t.tgrelid
     where c.oid = 'public.products'::regclass
       and t.tgname = 'trg_product_cogs_touch';
    if v_tgoid is null then
        raise exception 'trg_product_cogs_touch is not attached to products';
    end if;

    -- A trigger that is not column-scoped would fire on every product edit.
    if position('total_unit_cogs' in pg_get_triggerdef(v_tgoid)) = 0 then
        raise exception 'trg_product_cogs_touch is not scoped to total_unit_cogs';
    end if;

    if not exists (
        select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname = 'drain_product_cogs_queue'
           and p.prokind = 'p') then
        raise exception 'drain_product_cogs_queue was not created as a procedure';
    end if;

    raise notice
      'wiring in place: queue table, column-scoped trigger on products, drainer';
end $$;

commit;

-- ---------------------------------------------------------------------------
-- Schedule, OUTSIDE the transaction: cron.schedule commits its own work.
--
-- pg_cron is installed on prod but NOT on staging (free tier), so referencing
-- cron.* unguarded fails db-push-staging -- which is the rehearsal gate, so it
-- would never reach prod at all. Same shape as 20260728000008 and
-- 20260910000033: guard on pg_extension, unschedule-then-schedule rather than
-- relying on cron.schedule to upsert by name (version-dependent), and assert the
-- schedule only where cron actually exists.
--
-- Every minute, matching its two siblings: job 28 (drain_lot_recompute_queue)
-- and job 32 (roast_plan_drain). A product cost edit should reach its lines
-- within the minute, not overnight.
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron not installed -- skipping the drain schedule';
    return;
  end if;

  perform cron.unschedule(jobid) from cron.job where jobname = 'drain_product_cogs_queue';
  perform cron.schedule('drain_product_cogs_queue', '* * * * *',
                        $cron$CALL public.drain_product_cogs_queue()$cron$);

  if (select schedule from cron.job where jobname = 'drain_product_cogs_queue')
       is distinct from '* * * * *' then
    raise exception 'drain_product_cogs_queue did not take the every-minute schedule';
  end if;
  raise notice 'scheduled drain_product_cogs_queue every minute';
end
$$;
