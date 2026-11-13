-- A price nobody was ever billed may still be corrected.
--
-- propagate_price_log_to_orders is the "apply to past orders" true-up: the one
-- deliberate way a price entry reaches orders that already exist. Its target
-- set, from its own WHERE clause, is
--      order_status IN ('Delivered','Shipped')
--  AND invoice_number IS NULL AND invoice_sent_at IS NULL
--  AND shop_order_ref IS NULL AND NOT is_legacy_import
--  AND amount_override IS NULL AND quantity > 0
-- -- history that was delivered and never billed.
--
-- 🔴 EVERY ROW IN THAT SET IS NOW CLOSED. Delivered stamps the document, and
-- prod holds ZERO 'Shipped' orders, so after 20261112000003 the first line the
-- true-up touches raises and the WHOLE price entry rolls back. Not some rows:
-- the entire feature, every time.
--
-- Latent rather than live, which is why this is the last of the four and not
-- the first: backfill_orders has been ticked 0 times in 1,026 prod price-log
-- rows. It fires the first time anyone ticks "true up past orders". I told the
-- owner this one "breaks outright" and cited 379 price changes in 90 days --
-- that counted writes to the trigger's TABLE, not runs of its BODY.
--
-- WHAT IS DELIVERED DOES NOT MOVE; WHAT THEY WERE NEVER CHARGED MAY BE FIXED.
-- The exception is written as a property of the row, not as a sentinel the
-- caller sets, so nothing has to be trusted to be honest about who it is:
--   - quantity, product and the per-line override must not move -- that is
--     what was delivered, and it is a fact about goods in a customer's hands;
--   - the order must never have carried an invoice number, never have been
--     sent, and not be a shop order, whose confirmation email IS the figure
--     the buyer agreed to.
-- So the invariant the database defends is "a figure the customer has seen
-- never moves". The app rule the owner asked for -- editable until delivered
-- or sent -- is stricter than that, and assertInvoiceNotIssued still enforces
-- it, so no screen offers this. The gap is deliberate and is exactly the width
-- of the true-up.

begin;

-- Body is 20261112000003's, with one branch added before the locked-column
-- check and nothing else retyped.
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
  OR (NEW.amount_override  IS DISTINCT FROM OLD.amount_override) THEN
    RAISE EXCEPTION 'invoice % has gone to the customer, so its lines are locked — void it or issue a credit memo', OLD.order_id;
  END IF;
  RETURN NEW;
END;
$function$;

-- 🔴 AND THE FEATURE STILL RAISES ON THE PATH THE CRON DRIVES. A future-dated
-- "apply to past orders" is staged; cron job 27 touches the row hourly when
-- its date arrives, with no JWT, and guard_script_reprice refuses a repricing
-- from a session with no auth.uid() unless app.allow_price_backfill is set.
-- Worse, that job is ONE update over every price-log row due in the last three
-- days, so the raise aborts the whole statement: no due price applies that
-- hour, including unrelated ones, and it keeps failing every hour while the
-- row stays in the window -- which also stops trg_sync_product_price_from_log
-- moving products.price. This IS the deliberate repair the guard's own message
-- describes.
--
-- 🔴 NOT RETYPED. ALTER FUNCTION ... SET on a custom parameter needs
-- superuser, which the postgres role on Supabase is not, so the line goes in
-- the body -- read out, one statement inserted at an anchor asserted to occur
-- exactly once, written back. CREATE OR REPLACE rewrites ALL of a body, and
-- this function is 8kB of windowing arithmetic nobody should retype by hand.
do $$
declare v_src text; v_hits integer;
begin
  select p.prosrc into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'propagate_price_log_to_orders';
  if v_src is null then
    raise exception 'propagate_price_log_to_orders is gone, so the true-up has no body to repair';
  end if;

  if position('app.allow_price_backfill' in v_src) > 0 then
    raise notice 'the true-up already sets the backfill escape; left alone';
    return;
  end if;

  select count(*) into v_hits
    from regexp_matches(v_src, '    UPDATE public.order_details od', 'g');
  if v_hits <> 1 then
    raise exception 'the true-up body has % copies of its UPDATE anchor, not 1 — refusing to edit it blind', v_hits;
  end if;

  v_src := replace(v_src,
    '    UPDATE public.order_details od',
    '    -- The deliberate repair guard_script_reprice''s own message names.' || chr(10) ||
    '    PERFORM set_config(''app.allow_price_backfill'', ''on'', true);' || chr(10) ||
    '    UPDATE public.order_details od');

  execute format(
    'create or replace function public.propagate_price_log_to_orders() returns trigger language plpgsql security definer as %L',
    v_src);
end $$;

do $$
declare v_n integer;
begin
  -- Still routed through the one helper: the whole reason re-meaning the lock
  -- in 20261112000005 was a one-statement change.
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'guard_posted_order_detail_immutable'
                    and p.prosrc like '%order_document_is_closed%') then
    raise exception 'the detail guard no longer calls the helper';
  end if;

  -- The late-fee append survived the rewrite. It is the other sanctioned path
  -- and retyping this body is exactly how it would be lost.
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'guard_posted_order_detail_immutable'
                    and p.prosrc like '%app.late_fee_append%') then
    raise exception 'the late-fee append was dropped from the detail guard';
  end if;

  -- The true-up still refuses anything that was billed. If its WHERE clause
  -- ever loosened, the exception above would widen with it silently.
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'propagate_price_log_to_orders'
     and p.prosrc like '%o.invoice_number IS NULL%'
     and p.prosrc like '%o.invoice_sent_at IS NULL%'
     and p.prosrc like '%o.shop_order_ref IS NULL%';
  if v_n <> 1 then
    raise exception 'the true-up no longer restricts itself to never-billed orders, so the guard exception no longer matches it';
  end if;

  -- The cron escape landed, and the body it landed in is still the body.
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'propagate_price_log_to_orders'
                    and p.prosrc like '%app.allow_price_backfill%'
                    and p.prosrc like '%v_date_end%'
                    and p.prosrc like '%backfill_orders%'
                    and p.prosecdef) then
    raise exception 'the true-up still cannot reprice from the cron, or its body did not survive the edit';
  end if;
end $$;

-- ── Probes that RUN, each rolling itself back ─────────────────────────
-- 🔴 Every assertion above is a grep over prosrc: it proves the text is
-- there, not that the database behaves. These perform the real writes. The
-- carve-out and its two controls are a set -- a guard that let everything
-- through and a guard that let nothing through would each satisfy half of it.
do $$
declare v_line text; v_ord text; v_ok boolean;
begin
  select od.order_detail_id, od.order_id into v_line, v_ord
    from public.order_details od
    join public.orders o on o.order_id = od.order_id
   where o.document_closed_reason in ('delivered', 'shipped')
     and o.invoice_number is null and o.invoice_sent_at is null
     and o.shop_order_ref is null and not coalesce(o.is_legacy_import, false)
     and od.amount_override is null and od.quantity > 0
   limit 1;

  if v_line is null then
    raise warning 'NO DELIVERED, NEVER-BILLED LINE ON THIS DATABASE — the true-up carve-out is UNPROVEN here, not proven';
    return;
  end if;

  -- (a) MUST PASS: the true-up's own four columns, on its own target set.
  --
  -- 🔴 THE VALUES HAVE TO MOVE. Every guard here tests IS DISTINCT FROM, so
  -- `set total_price = total_price` passes whether or not the carve-out
  -- exists -- which is what this probe was, and it would have reported green
  -- on a batch that had silently lost the carve-out altogether.
  --
  -- 🔴 And set the backfill flag first, or guard_script_reprice refuses the
  -- write for a reason that has nothing to do with what is being proven: psql
  -- carries no JWT, and a probe that errors for the wrong reason is not a
  -- result.
  begin
    perform set_config('app.allow_price_backfill', 'on', true);
    update public.order_details
       set unit_price_at_sale = coalesce(unit_price_at_sale, 0) + 0.01,
           list_price_total   = coalesce(list_price_total, 0) + 0.01 * quantity,
           total_price        = coalesce(total_price, 0) + 0.01 * quantity,
           discount_amount    = coalesce(discount_amount, 0)
     where order_detail_id = v_line;
    raise exception 'PROBE_ROLLBACK';
  exception when others then
    if SQLERRM <> 'PROBE_ROLLBACK' then
      raise exception 'the true-up still cannot correct a price nobody was billed: %', SQLERRM;
    end if;
  end;

  -- (b) MUST FAIL: the discount inputs, which derive the money through a
  -- trigger that runs before this guard ever looks.
  v_ok := false;
  begin
    update public.order_details
       set discount_kind = 'percent', discount_value = 100
     where order_detail_id = v_line;
  exception when others then
    v_ok := true;
  end;
  if not v_ok then
    raise exception 'a closed line''s discount can still be rewritten, which restates its money and its COGS';
  end if;

  -- (c) MUST FAIL: the quantity, which is a fact about goods in a customer's
  -- hands and is the thing the carve-out exists NOT to touch.
  v_ok := false;
  begin
    update public.order_details set quantity = quantity + 1 where order_detail_id = v_line;
  exception when others then
    v_ok := true;
  end;
  if not v_ok then
    raise exception 'what was delivered can still be changed — the carve-out is wider than a price correction';
  end if;
end $$;

commit;
