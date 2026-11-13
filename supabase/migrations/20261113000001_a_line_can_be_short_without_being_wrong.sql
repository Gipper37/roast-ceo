-- A LINE CAN BE SHORT WITHOUT BEING WRONG
--
-- Owner, 2026-11-13: "We need to add an option for all staff to be able to mark
-- certain items out of stock on an invoice and the invoice amount to be updated
-- accordingly, not charging for that item. It also needs to be possible to
-- choose amounts of a total out of stock. So someone ordered 10 monins but we
-- only had 9. So they need to be able to mark only 1 of the 10 out of stock."
-- And on what the line should then read: "make it 9 and 1 out of stock or
-- something like that. or 9/10 9 of 10 with a note, out of stock."
--
-- 🔴 THERE IS NO INVOICE TABLE. An invoice's lines ARE order_details rows and
-- its header IS the orders row -- an invoice is the order, rendered. So "do not
-- charge for this one" is a change to the order line, and everything that
-- reads that line moves with it.
--
-- WHICH IS WHY THE SHORT LOWERS `quantity` RATHER THAN SITTING BESIDE IT.
-- Nothing in this schema deducts stock transactionally: consumable stock,
-- COGS, roast demand and the pack totals are all RECOMPUTED from
-- order_details.quantity -- 26 functions and 9 views read it directly. A
-- second "supplied" column would have to be taught to every one of them, and
-- each one that was missed would keep billing, roasting and deducting for a
-- bottle that never left the shelf, silently. Lowering quantity makes the
-- money, the stock, the roast plan and the COGS all correct at once, for free.
--
-- `quantity_ordered` therefore holds what the customer ASKED for, and nothing
-- computes from it. It exists so the line can still say "9 of 10", which is
-- what the owner asked to see, without any of those 35 readers changing.
--
-- 🔴 AND IT IS A PACKING-TIME ACT, NOT AN ACCOUNTING ONE. The window is
-- `order_figures_are_final` -- once the customer has been shown a number, a
-- short is a credit memo, not an edit. guard_posted_order_detail_immutable
-- already enforces the harder half of that (12,156 of 16,058 prod orders are
-- closed), and this migration extends it to cover the two new columns: a line
-- whose quantity is frozen but whose "ordered" figure can still move would say
-- "9 of 12" about an order for 10.

begin;

-- ─────────────────────────────────────────────────────────────────────────
-- 1. What was asked for, beside what is being charged for.
-- ─────────────────────────────────────────────────────────────────────────
alter table public.order_details add column if not exists quantity_ordered numeric;
alter table public.order_details add column if not exists short_reason text;

comment on column public.order_details.quantity_ordered is
  'What the customer asked for, when that differs from what we are billing. NULL means nothing was short and `quantity` is the whole story. Written once, the first time a line is shorted, so a second short does not overwrite the original figure. 🔴 NOTHING COMPUTES FROM THIS. Money, stock, roast demand and COGS all derive from `quantity`, which carries the supplied figure; this column exists so the document can read "9 of 10" without any of those readers changing.';

comment on column public.order_details.short_reason is
  'Why the line is short, shown to the customer beside the quantity. Today the only writer is the out-of-stock action and the only value is "Out of stock"; it is free text rather than an enum so a damaged or substituted line does not need a migration to say so. NULL whenever quantity_ordered is NULL.';

-- 🔴 A FULL SHORT IS THE OWNER'S FIRST SENTENCE, AND THE CHECK REFUSED IT.
-- "mark certain items out of stock on an invoice and the invoice amount to be
-- updated accordingly, not charging for that item" describes a line supplied
-- ZERO -- and `order_details_quantity_positive` (quantity > 0) refuses exactly
-- that, so the headline case of this feature would have failed at the database
-- with a constraint name in front of a packer. Found by reading the
-- constraint, not by trying it.
--
-- So the constraint LEARNS THE ONE CASE instead of being dropped: zero is
-- allowed only on a line that says why it is zero. It keeps doing its real job
-- -- no accidental zero-quantity line, which is what the 26 functions and 9
-- views reading od.quantity assume -- while admitting a short, and the
-- admission is legible in the row itself rather than in a comment.
--
-- 🔴 Nothing divides by quantity. Checked BEFORE relaxing this, because a zero
-- that reaches a divisor is a 22012 in front of the same packer: no SQL
-- function and no view divides by it at all, and the one frontend site that
-- does (lib/shop/invoiceDispatch.ts:391, the unit-price fallback) already
-- guards `qty !== 0`.
--
-- Re-added NOT VALID, exactly as it stands today. All 26,419 prod lines
-- already satisfy the new predicate -- 0 of them carry quantity 0 -- so a
-- validating scan would prove nothing while holding a lock on the largest
-- table here.
alter table public.order_details drop constraint if exists order_details_quantity_positive;
alter table public.order_details add constraint order_details_quantity_positive
  check (quantity > 0 or short_reason is not null) not valid;

-- ─────────────────────────────────────────────────────────────────────────
-- 2. Who may do it.
--
-- 🔴 "ALL STAFF" IS NOT A KEY THAT EXISTS. Exactly one permission is held by
-- all 11 roles (equipment.view) and it is plan-gated, so on a starter tenant
-- nothing at all is universal. The owner's words were "people that pack and
-- above. staff and above, no sales person though" -- which is precisely the
-- seven roles that hold `order.pack`, and sales_person holds neither pack nor
-- edit, so it is excluded by naming the seven rather than by a rule.
--
-- A NEW KEY RATHER THAN `order.pack`, because this one moves money and that
-- one does not; and NOT `order.edit`, which is the key every existing per-line
-- money control uses and which the `staff` role does not hold -- the role the
-- owner actually named. Not plan-gated: a short is not a feature, it is what
-- happens when the shelf is empty.
-- ─────────────────────────────────────────────────────────────────────────
insert into public.permissions
  (permission_id, category, label, description, default_deny_message, is_plan_gated, sort_order)
values
  ('order.out_of_stock', 'Orders', 'Mark order lines out of stock',
   'Mark some or all of an order line out of stock before it is invoiced: the quantity drops to what was actually supplied, the order total follows, and the line records what was originally ordered. Distinct from edit — the person at the shelf can report a shortage without being able to change prices.',
   'You don''t have permission to do that. Contact your administrator if you need access.',
   false, 26)
on conflict (permission_id) do update
  set category = excluded.category, label = excluded.label,
      description = excluded.description, is_plan_gated = excluded.is_plan_gated;

insert into public.role_permissions (role_id, permission_id, granted)
select r, 'order.out_of_stock', true
  from unnest(array['company_admin','facility_admin','manager','roastery_manager',
                    'roastmaster','assistant_roaster','staff']) as r
on conflict (role_id, permission_id) do update set granted = true;

insert into public.plan_permissions (plan_id, permission_id, granted)
select p, 'order.out_of_stock', true
  from unnest(array['starter','pro','enterprise','enterprise_plus']) as p
on conflict (plan_id, permission_id) do update set granted = true;

-- ─────────────────────────────────────────────────────────────────────────
-- 3. The closed-document guard learns the two new columns.
--
-- 🔴 THIS IS PROD'S OWN pg_get_functiondef OUTPUT with two insertions made by
-- exact string match -- not a retyped body. CREATE OR REPLACE rewrites all of
-- it, so anything retyped from memory is silently lost; everything below that
-- is not the two new lines is byte-for-byte what is running today.
--
-- Both lists, not one. The first is the carve-out that lets a delivered-but-
-- never-billed order have its PRICE corrected: a change to these columns is
-- not a price correction, so it must fall through to the refusal. The second
-- is the refusal itself.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.guard_posted_order_detail_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE v_posted boolean; v_type text;
BEGIN
  v_posted := public.order_document_is_closed(COALESCE(NEW.order_id, OLD.order_id));

  IF NOT COALESCE(v_posted, false) THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- 🔴 THE QUICKBOOKS IMPORTER BUILDS ITS HEADERS 'Delivered' AND INSERTS THE
  -- LINES AS A SECOND STATEMENT, so once a header stamps closed on INSERT
  -- every line of every imported invoice is refused -- nothing imports. And
  -- revertQbImport deletes children first by design, so a half-landed batch
  -- cannot be undone through the product either. Imported history is already
  -- unreachable from every screen and refused by finalize_invoice, and
  -- guard_order_invoice_columns and handle_order_detail_logic both carve it
  -- out exactly here; this guard was the one that did not.
  IF EXISTS (SELECT 1 FROM public.orders o
              WHERE o.order_id = COALESCE(NEW.order_id, OLD.order_id)
                AND COALESCE(o.is_legacy_import, false)) THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'invoice % has gone to the customer — void it or issue a credit memo', OLD.order_id;
  END IF;
  IF TG_OP = 'INSERT' THEN
    -- The one sanctioned append: a late-fee line, inserted by apply_late_fee
    -- in THIS transaction (the sentinel names the order). Product type alone
    -- was spoofable over PostgREST — RLS is tenancy-only (review P1).
    SELECT p.product_type INTO v_type FROM public.products p WHERE p.product_id = NEW.product_id;
    IF v_type = 'ptype_late_fee'
       AND current_setting('app.late_fee_append', true) = NEW.order_id THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'invoice % has gone to the customer — void it or issue a credit memo', NEW.order_id;
  END IF;

  -- Correcting the price of something nobody was ever billed for. What was
  -- delivered is untouched: quantity, product and the override all stand. See
  -- the header — this is the width of the "apply to past orders" true-up and
  -- nothing else, and it is decided from the row, not from a caller's claim.
  -- 🔴 PIN THE DISCOUNT INPUTS, NOT ONLY THE OUTPUTS. trg_handle_order_details
  -- sorts BEFORE this guard and derives list_price_total, discount_amount,
  -- total_price, unit_cost_at_sale and roasted_weight from discount_kind and
  -- discount_value. So an exception that let those two through was not a
  -- price correction at all: one PATCH of {"discount_kind":"percent",
  -- "discount_value":100} took a closed line's net to zero, restated
  -- orders.order_total through update_order_aggregates, and re-stamped the
  -- line's COGS at TODAY's product cost -- which is what customer_profitability
  -- reads. 12,001 closed orders / 26,419 lines / $5.2m of line money.
  --
  -- The true-up itself never writes them (it SETs only unit_price_at_sale,
  -- list_price_total, discount_amount, total_price), so pinning them costs
  -- the feature nothing and makes the exception exactly its own width.
  --
  -- 🔴 AND ASK THE REASON, NOT THE INVOICE NUMBER. 20261112000005 added two
  -- terms the old expression could not reach -- money recorded, and
  -- voided/written off -- because the owner's rule is "if a payment has been
  -- recorded it shouldn't be editable" and "not editable if voided". Inferring
  -- "never billed" from invoice_number re-admitted every one of those rows
  -- that happens to carry no STRATA number: three prod orders are Delivered
  -- with paid_at stamped and no number today, one of them carrying $91.10.
  -- document_closed_reason is the column that was added for this question.
  IF  NEW.quantity         IS NOT DISTINCT FROM OLD.quantity
  AND NEW.product_id       IS NOT DISTINCT FROM OLD.product_id
  AND NEW.amount_override  IS NOT DISTINCT FROM OLD.amount_override
  AND NEW.discount_kind    IS NOT DISTINCT FROM OLD.discount_kind
  AND NEW.discount_value   IS NOT DISTINCT FROM OLD.discount_value
  AND NEW.discount_source  IS NOT DISTINCT FROM OLD.discount_source
  AND NEW.discount_rule_id IS NOT DISTINCT FROM OLD.discount_rule_id
  AND NEW.quantity_ordered IS NOT DISTINCT FROM OLD.quantity_ordered
  AND NEW.short_reason     IS NOT DISTINCT FROM OLD.short_reason
  AND EXISTS (SELECT 1 FROM public.orders o
               WHERE o.order_id = NEW.order_id
                 AND o.document_closed_reason IN ('delivered', 'shipped')
                 AND o.invoice_number  IS NULL
                 AND o.invoice_sent_at IS NULL
                 AND o.shop_order_ref  IS NULL
                 AND NOT COALESCE(o.is_legacy_import, false)
                 -- 🔴 THE REASON CANNOT ANSWER "HAS ANYONE BEEN BILLED". It
                 -- records what closed the document FIRST, and the CASE that
                 -- writes it ranks 'delivered' above 'paid' because delivery
                 -- comes first in the real workflow. So a delivered order
                 -- whose payment was recorded still reads 'delivered' -- the
                 -- three prod orders this carve-out's own comment names are
                 -- exactly those, one of them carrying $91.10. Ask the money.
                 AND o.paid_at IS NULL
                 AND COALESCE(o.invoice_state, '') NOT IN ('paid', 'partial')
                 AND NOT EXISTS (SELECT 1 FROM public.invoice_payment_allocations a
                                   JOIN public.invoice_payments ip ON ip.payment_id = a.payment_id
                                  WHERE a.order_id = o.order_id
                                    AND ip.voided_at IS NULL)) THEN
    RETURN NEW;
  END IF;

  -- Every number the invoice shows, not just the net. A discount that can move
  -- while total_price stands still is a silently restated invoice.
  IF (NEW.quantity         IS DISTINCT FROM OLD.quantity)
  OR (NEW.product_id       IS DISTINCT FROM OLD.product_id)
  OR (NEW.total_price      IS DISTINCT FROM OLD.total_price)
  OR (NEW.list_price_total IS DISTINCT FROM OLD.list_price_total)
  OR (NEW.discount_kind    IS DISTINCT FROM OLD.discount_kind)
  OR (NEW.discount_value   IS DISTINCT FROM OLD.discount_value)
  OR (NEW.discount_amount  IS DISTINCT FROM OLD.discount_amount)
  OR (NEW.amount_override  IS DISTINCT FROM OLD.amount_override)
  OR (NEW.quantity_ordered IS DISTINCT FROM OLD.quantity_ordered)
  OR (NEW.short_reason     IS DISTINCT FROM OLD.short_reason) THEN
    RAISE EXCEPTION 'invoice % has gone to the customer, so its lines are locked — void it or issue a credit memo', OLD.order_id;
  END IF;
  RETURN NEW;
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────
-- 4. Prove it, on this database's own rows.
-- ─────────────────────────────────────────────────────────────────────────
do $verify$
declare
  v_open   text;
  v_closed text;
  v_roles  int;
  v_plans  int;
begin
  -- The rows exist at all.
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='order_details'
                    and column_name in ('quantity_ordered','short_reason')
                 having count(*) = 2) then
    raise exception 'the two columns a short needs are not both there';
  end if;

  select count(*) into v_roles from public.role_permissions
   where permission_id = 'order.out_of_stock' and granted;
  select count(*) into v_plans from public.plan_permissions
   where permission_id = 'order.out_of_stock' and granted;
  if v_roles <> 7 then
    raise exception 'order.out_of_stock reaches % roles, not the seven that pack', v_roles;
  end if;
  if v_plans <> 4 then
    raise exception 'order.out_of_stock is on % plans, not all four', v_plans;
  end if;
  -- 🔴 A KEY AND ITS POLICY MUST ADMIT THE SAME ROLES, and both directions
  -- fail silently. sales_person was named by the owner as the exclusion, so
  -- assert the exclusion rather than only the count.
  if exists (select 1 from public.role_permissions
              where permission_id = 'order.out_of_stock'
                and role_id in ('sales_person','accounting_admin','accounting_view','equipment_tech')
                and granted) then
    raise exception 'order.out_of_stock reaches a role that is not on the floor';
  end if;

  -- (a) MUST FAIL: the ordered figure cannot move on a closed document.
  --     A line whose quantity is frozen but whose "ordered" can still be
  --     rewritten would read "9 of 12" about an order for 10.
  select d.order_detail_id into v_closed
    from public.order_details d
    join public.orders o on o.order_id = d.order_id
   where o.document_closed_at is not null
     and o.invoice_number is not null
     and d.parent_order_detail_id is null
   limit 1;
  if v_closed is not null then
    declare v_refused boolean := false;
    begin
      begin
        update public.order_details
           set quantity_ordered = coalesce(quantity_ordered, quantity) + 1
         where order_detail_id = v_closed;
      exception when others then
        v_refused := true;
      end;
      if not v_refused then
        raise exception 'a closed line can still be told it was ordered in a different quantity';
      end if;
    end;
  else
    raise notice 'no closed line to probe against on this database; skipped (a)';
  end if;

  -- (b) MUST PASS: an open line takes a short, and the money follows.
  --     🔴 The values have to MOVE -- every guard here tests IS DISTINCT FROM,
  --     so `set quantity = quantity` would pass whether or not any of this
  --     works. Rolled back by raising, so this proves the write and keeps the
  --     database exactly as it found it.
  select d.order_detail_id into v_open
    from public.order_details d
    join public.orders o on o.order_id = d.order_id
   where o.document_closed_at is null
     and not public.order_figures_are_final(o.order_id)
     and d.parent_order_detail_id is null
     and d.quantity >= 2
   limit 1;
  if v_open is null then
    raise notice 'no open line with a quantity to short on this database; skipped (b)';
  else
    begin
      update public.order_details
         set quantity_ordered = quantity,
             short_reason     = 'Out of stock',
             quantity         = quantity - 1
       where order_detail_id = v_open;
      raise exception 'PROBE_ROLLBACK';
    exception when others then
      if SQLERRM <> 'PROBE_ROLLBACK' then
        raise exception 'an open line cannot be marked short: %', SQLERRM;
      end if;
    end;
  end if;

  -- (c) MUST PASS and (d) MUST FAIL: the relaxed constraint, both ways.
  --     🔴 ONE DIRECTION IS NOT A PROOF. A check that only admits would pass
  --     if I had dropped the constraint outright, and one that only refuses
  --     would pass if I had left it alone -- the two mistakes this edit sits
  --     between. Same line, same transaction, opposite verdicts.
  if v_open is not null then
    declare v_zero_refused boolean := false;
    begin
      -- (c) zero WITH a reason: the whole line is out of stock.
      begin
        update public.order_details
           set quantity_ordered = quantity,
               short_reason     = 'Out of stock',
               quantity         = 0
         where order_detail_id = v_open;
        raise exception 'PROBE_ROLLBACK';
      exception when others then
        if SQLERRM <> 'PROBE_ROLLBACK' then
          raise exception 'a line supplied zero cannot be recorded, which is the feature: %', SQLERRM;
        end if;
      end;
      -- (d) zero with NO reason: still refused, or the constraint is gone.
      begin
        update public.order_details set quantity = 0 where order_detail_id = v_open;
      exception when others then
        v_zero_refused := true;
      end;
      if not v_zero_refused then
        raise exception 'a line can be zeroed without saying why -- the quantity constraint is not doing its job';
      end if;
    end;
  end if;
end $verify$;

commit;
