-- The review's teeth, and the door for imported open A/R.
--
-- The adversarial review of the late-fee build confirmed three holes, all
-- fixed here rather than by amending the staged 000001:
--
-- 1. The posted-line guard's carve-out keyed only on product_type — RLS is
--    tenancy-only, so ANY company member could append fee-typed lines to a
--    posted invoice over PostgREST with any amount, bypassing rate, cadence,
--    state and permission. Now the carve-out admits an insert only while
--    apply_late_fee's transaction-local sentinel names that exact order.
--
-- 2. apply_late_fee itself is REST-callable, so the ar.late_fee_apply gate
--    lives in the DATABASE too: the caller's team role must hold the key.
--    (Plain psql / service paths have no auth.uid() and pass — same trust as
--    every other service-role path.)
--
-- 3. waiveLateFee could waive the same fee forever — nothing recorded WHICH
--    fee a memo forgave. credit_memos.waived_order_detail_id + a partial
--    unique index makes a second waive of the same live fee impossible at the
--    DB, and gives the UI the fact it needs to say "waived" instead of
--    offering the button again.
--
-- And the owner's ask: imported OPEN A/R ($164,949 across 209 QB invoices,
-- all reconciled to the cent against their lines) should be adoptable into
-- STRATA A/R — posted, aging, payable, feeable — without emailing anyone.
-- Two function changes make an adopted (posted) legacy invoice a first-class
-- citizen: apply_late_fee stops refusing on the legacy flag (posted + state
-- are the real gates), and the fee line carries explicit money columns
-- because the engine deliberately skips repricing legacy rows. The adoption
-- itself is tenant data surgery and lives in scripts/, not here.

begin;

-- ── 3a. The waiver leaves a pointer ──────────────────────────────────────────
alter table public.credit_memos
  add column if not exists waived_order_detail_id text;

create unique index if not exists uq_credit_memos_waived_line_live
  on public.credit_memos (waived_order_detail_id)
  where waived_order_detail_id is not null and voided_at is null;

-- ── 3b. create_credit_memo carries it atomically ─────────────────────────────
CREATE OR REPLACE FUNCTION public.create_credit_memo(p_company_id text, p_customer_id text, p_amount_cents bigint, p_applied_to_order_id text, p_reason text, p_created_by text, p_credit_date date DEFAULT CURRENT_DATE, p_waived_order_detail_id text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE v_seq bigint; v_num text; v_cm_id text;
BEGIN
  IF p_company_id NOT IN (SELECT auth_company_ids()) THEN
    RAISE EXCEPTION 'not authorized for company %', p_company_id;
  END IF;
  IF COALESCE(p_amount_cents,0) <= 0 THEN RAISE EXCEPTION 'amount must be positive'; END IF;

  -- Allocated INSIDE this transaction so a guard rejection rolls the sequence bump
  -- back and numbering stays gap-free. Never call this to "preview" a number.
  SELECT a.credit_memo_sequence, a.credit_memo_number INTO v_seq, v_num
    FROM public.allocate_credit_memo_number(p_company_id) a;

  v_cm_id := gen_random_uuid()::text;
  INSERT INTO public.credit_memos
    (credit_memo_id, company_id, customer_id, credit_memo_number, credit_memo_sequence,
     amount_cents, applied_to_order_id, reason, created_by, credit_date, waived_order_detail_id)
  VALUES
    (v_cm_id, p_company_id, p_customer_id, v_num, v_seq,
     p_amount_cents, NULLIF(p_applied_to_order_id,''), p_reason, p_created_by,
     COALESCE(p_credit_date, current_date), NULLIF(p_waived_order_detail_id,''));
  -- The partial unique index turns a concurrent double-waive into an error
  -- HERE, inside the same transaction as the number allocation — gap-free
  -- either way.

  RETURN jsonb_build_object('ok', true, 'credit_memo_number', v_num, 'credit_memo_id', v_cm_id);
END;
$function$;

-- ── 1+2. apply_late_fee: DB-side permission, sentinel, adoption support ──────
create or replace function public.apply_late_fee(p_order_id text)
returns numeric
language plpgsql
as $function$
declare
  v_order      record;
  v_role       text;
  v_pct        numeric;
  v_paid_cents bigint;
  v_balance    numeric;
  v_fee        numeric;
  v_product_id text;
  v_group_id   uuid;
begin
  select o.order_id, o.company_id, o.facility_id, o.posted, o.invoice_state,
         o.due_date,
         (coalesce(o.order_total,0) + coalesce(o.tax_amount,0)) as doc_total
    into v_order
    from public.orders o
   where o.order_id = p_order_id
   for update;
  if not found then raise exception 'order % not found', p_order_id; end if;

  -- REST-callable, so the permission gate lives here too, not only in the
  -- server action. No auth context (psql, service role) passes — the same
  -- trust every service path already carries.
  if auth.uid() is not null then
    select t.role into v_role
      from public.team t
     where t.auth_user_id = auth.uid()
       and t.company_id = v_order.company_id
       and t.is_active
     limit 1;
    if v_role is null or not exists (
      select 1 from public.role_permissions rp
       where rp.role_id = v_role
         and rp.permission_id = 'ar.late_fee_apply'
         and rp.granted
    ) then
      raise exception 'your role cannot apply late fees';
    end if;
  end if;

  -- Posted + a collectable state are the gates. The legacy-import flag is
  -- deliberately NOT one: an ADOPTED imported invoice (posted by the
  -- adoption script) ages and fees like any other. Un-adopted history is
  -- never posted, so it can never arrive here.
  if not coalesce(v_order.posted, false)
     or v_order.invoice_state not in ('open','overdue','partial') then
    raise exception 'late fees apply to open, partial or overdue STRATA invoices only (this one is %)',
      coalesce(v_order.invoice_state, 'not issued');
  end if;
  if v_order.due_date is null or v_order.due_date >= current_date then
    raise exception 'invoice % is not past due', p_order_id;
  end if;

  select late_fee_percent into v_pct
    from public.billing_settings where company_id = v_order.company_id;
  if v_pct is null or v_pct <= 0 then
    raise exception 'no standard late fee is set — add one in Configuration first';
  end if;

  -- Monthly cadence, enforced where the click can't break it.
  if exists (
    select 1 from public.order_details od
    join public.products p on p.product_id = od.product_id
    where od.order_id = p_order_id
      and p.product_type = 'ptype_late_fee'
      and od.created_at > now() - interval '28 days'
  ) then
    raise exception 'a late fee was already added to % in the last 28 days', p_order_id;
  end if;

  -- The balance the fee compounds on: document total (any prior fees
  -- included) minus live payments and credit memos — the recompute's math.
  select coalesce(sum(a.amount_cents),0) into v_paid_cents
    from public.invoice_payment_allocations a
    join public.invoice_payments p on p.payment_id = a.payment_id
   where a.order_id = p_order_id and p.voided_at is null;
  v_paid_cents := v_paid_cents + coalesce((select sum(amount_cents)
    from public.credit_memos where applied_to_order_id = p_order_id and voided_at is null), 0);

  v_balance := v_order.doc_total - (v_paid_cents / 100.0);
  v_fee := round(v_balance * v_pct / 100.0, 2);
  if v_fee <= 0 then
    raise exception 'nothing outstanding on % — no fee to charge', p_order_id;
  end if;

  -- The company's Late fee product, created on first use. Non-sellable by
  -- type, so it exists for these lines and appears in no picker or shop.
  select p.product_id into v_product_id
    from public.products p
   where p.company_id = v_order.company_id
     and p.product_type = 'ptype_late_fee'
     and p.is_active
   limit 1;
  if v_product_id is null then
    v_group_id := gen_random_uuid();
    insert into public.product_groups (group_id, group_name, product_type, company_id, facility_id)
    values (v_group_id, 'Late fee', 'ptype_late_fee', v_order.company_id, v_order.facility_id);
    v_product_id := gen_random_uuid()::text;
    insert into public.products (product_id, product_name, group_id, product_type,
                                 company_id, facility_id, is_active)
    values (v_product_id, 'Late fee', v_group_id, 'ptype_late_fee',
            v_order.company_id, v_order.facility_id, true);
  end if;

  -- The sentinel the guard demands: only THIS function, having passed every
  -- check above, may append to a posted invoice — and only for this order,
  -- only within this transaction. A raw PostgREST insert has no sentinel and
  -- dies in the guard like any other tampering (review P1).
  perform set_config('app.late_fee_append', p_order_id, true);

  -- Money columns are explicit because handle_order_detail_logic deliberately
  -- skips repricing legacy rows — an ADOPTED imported invoice would otherwise
  -- get a fee line with no dollars on it. On native rows the trigger derives
  -- the same values from amount_override; writing both keeps one truth.
  insert into public.order_details (order_detail_id, order_id, product_id,
                                    quantity, amount_override,
                                    unit_price_at_sale, list_price_total,
                                    discount_amount, total_price, item_status)
  values (gen_random_uuid()::text, p_order_id, v_product_id, 1, v_fee,
          v_fee, v_fee, 0, v_fee, 'Delivered');

  perform set_config('app.late_fee_append', '', true);

  return v_fee;
end;
$function$;

-- ── 1. The guard trusts the sentinel, not the product type ───────────────────
CREATE OR REPLACE FUNCTION public.guard_posted_order_detail_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE v_posted boolean; v_type text;
BEGIN
  SELECT posted INTO v_posted FROM public.orders
   WHERE order_id = COALESCE(NEW.order_id, OLD.order_id);

  IF NOT COALESCE(v_posted, false) THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'cannot remove a line from posted invoice % — void or issue a credit memo', OLD.order_id;
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
    RAISE EXCEPTION 'cannot add a line to posted invoice % — void or issue a credit memo', NEW.order_id;
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
    RAISE EXCEPTION 'line on posted invoice % is locked — void or issue a credit memo', OLD.order_id;
  END IF;
  RETURN NEW;
END;
$function$;

commit;

notify pgrst, 'reload schema';
