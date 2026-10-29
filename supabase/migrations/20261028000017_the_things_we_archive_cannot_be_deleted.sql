-- The things this app archives cannot be deleted.
--
-- ── The question that produced this ──────────────────────────────────────
--
-- "if we archive everything why is there even places to delete."
--
-- Right, and the codebase already agrees. Every delete in the app was read and
-- classified before writing this. All 27 tables with a delete call fall into
-- four kinds, and none of them is a RECORD:
--
--   line edits          a line off an order, a BOM, a recipe, an estimate, a
--                       standing order, a VMI check-in, a delivery day. Taking
--                       a line off the thing you are editing is editing, not
--                       archiving.
--   drafts, working data roast_temp_nodes, roast_events, roast_sessions,
--                       staged_line_items, and a DRAFT recall -- that last one
--                       bounded by .eq('status','draft') with the comment "a
--                       finalised record is a record".
--   small config lists  tax rules, restock categories, parts catalog,
--                       maintenance programs, labour rates, market alerts.
--   rollback            roast_log rows from a failed Artisan import, orders
--                       from a failed create.
--
-- products, product_groups and customers appear in NONE of them. Zero delete
-- calls in the app, zero database functions that delete them. They are
-- archived (`is_active`) or tombstoned (`canonical_*`). The DELETE privilege on
-- them is a Supabase default nobody chose, exactly like the TRUNCATE revoked in
-- 20261028000016.
--
-- ── Why it is worth removing rather than leaving ─────────────────────────
--
-- 🔴 The cascades. One deleted `customers` row also deletes
-- customer_notes_detail, shop_invitations, customer_users, email_log,
-- standing_order_lines, vmi_checkins, equipment, customer_delivery_day,
-- customer_discount and customer_payment_methods -- TEN tables, in one
-- statement, with nothing to confirm it. products cascades to five:
-- products_price_log, product_consumables, vmi_checkin_items, product_label,
-- pack_stock_count.
--
-- ── Why a REVOKE and not a policy ────────────────────────────────────────
--
-- A policy can be undone by a permissive policy added beside it -- permissive
-- policies are OR-ed, which is the exact trap a cmd=ALL survivor sets for a
-- gated DELETE, and the reason the earlier batches replaced those policies
-- rather than adding to them. A revoke removes the capability itself; no later
-- policy can hand it back by accident.
--
-- And it fails in the right direction. If a feature one day needs to delete a
-- customer, it stops with "permission denied for table customers" rather than
-- quietly taking ten tables of their history with it. Granting it back for one
-- path is a line -- better, a SECURITY DEFINER function that checks a key first.
--
-- 🔴 customers already has NO UPDATE grant to authenticated, and that is not a
-- mistake: this database already uses revokes to take capabilities away where
-- the writes go through something else. This is the same move, for delete.

begin;

revoke delete on public.products       from authenticated;
revoke delete on public.product_groups from authenticated;
revoke delete on public.customers      from authenticated;

do $$
declare t text; n_del int; n_sel int; n_ins int;
begin
  foreach t in array array['products','product_groups','customers'] loop
    select count(*) into n_del from pg_class c join pg_namespace n on n.oid=c.relnamespace
     where n.nspname='public' and c.relname=t and has_table_privilege('authenticated', c.oid, 'DELETE');
    if n_del <> 0 then raise exception 'authenticated can still DELETE from %', t; end if;

    -- 🔴 And the app must still work. A revoke that took reading or creating
    -- with it would be a far worse outage than the thing being removed.
    select count(*) into n_sel from pg_class c join pg_namespace n on n.oid=c.relnamespace
     where n.nspname='public' and c.relname=t and has_table_privilege('authenticated', c.oid, 'SELECT');
    select count(*) into n_ins from pg_class c join pg_namespace n on n.oid=c.relnamespace
     where n.nspname='public' and c.relname=t and has_table_privilege('authenticated', c.oid, 'INSERT');
    if n_sel <> 1 or n_ins <> 1 then
      raise exception 'the revoke took SELECT or INSERT with it on % (select=%, insert=%)', t, n_sel, n_ins;
    end if;
  end loop;

  -- UPDATE is asserted only where it existed. customers never had it, and
  -- asserting it there would fail for a reason that has nothing to do with
  -- this change.
  if not has_table_privilege('authenticated', 'public.products', 'UPDATE')
     or not has_table_privilege('authenticated', 'public.product_groups', 'UPDATE') then
    raise exception 'the revoke took UPDATE with it on products or product_groups';
  end if;

  raise notice 'products, product_groups and customers can be archived but no longer deleted';
end $$;

commit;
