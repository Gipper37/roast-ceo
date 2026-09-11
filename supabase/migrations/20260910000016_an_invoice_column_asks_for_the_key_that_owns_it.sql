-- An invoice column asks for the key that owns it.
--
-- `orders` cannot take the treatment 20260910000014 gave the money tables. A row
-- policy keyed on an invoice permission would refuse every ordinary write to the
-- table — createOrder, the pack toggles, delivery, updateOrder, the standing-order
-- cron's drafts, the Shopify import. The invoice and payment fields need gating;
-- the row does not.
--
-- So the row policy stays tenancy-only and the COLUMNS are guarded here, the way
-- guard_team_privileged_columns guards role and company_id. Each group asks for
-- the key its own server action already asks for:
--
--   invoice_number, invoice_sequence, posted, invoice_state -> draft/open
--                                     invoice.send, or billing.configure, or
--                                     config.import_data on a legacy import row
--   invoice_sent_at                   invoice.send
--   invoice_state -> void, voided_at, supersedes_invoice_number,
--   superseded_by_order_id            invoice.void
--   invoice_state -> written_off, written_off_at
--                                     invoice.write_off
--   invoice_state -> paid/partial/overdue, paid_at
--                                     payment.record, payment.charge_card,
--                                     ar.late_fee_apply, invoice.void,
--                                     invoice.write_off or billing.configure
--   due_date, payment_terms           payments.terms_edit, invoice.send or
--                                     billing.configure
--   aging_excluded                    billing.configure, or config.import_data
--                                     on a legacy import row
--   payment_status                    nobody with a JWT. Every writer is the
--                                     service role: the storefront checkout and
--                                     the ActivityPay webhook.
--
-- This also closes a hole the policies could not reach. finalize_invoice,
-- recompute_invoice_ar_state, recompute_overdue_invoices, apply_open_ar and
-- commit_cutover are all SECURITY INVOKER, EXECUTE to authenticated, and none of
-- them checks a permission — so any team member could post, void or re-state an
-- invoice by calling them over PostgREST. They run as the caller, so this trigger
-- sees the real identity and refuses.
--
-- Callers with no JWT — service role, pg_cron's overdue sweep, migrations — are
-- exempt, as everywhere else.
--
-- Prod today: STRATA invoicing is not released (the owner has never sent one),
-- so nothing in flight depends on these paths.

begin;

create or replace function public.guard_order_invoice_columns()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_co       text := new.company_id;
  v_ins      boolean := (tg_op = 'INSERT');
  v_legacy   boolean := coalesce(new.is_legacy_import, false);
  v_send     boolean;
  v_void     boolean;
  v_writeoff boolean;
  v_billing  boolean;
  v_terms    boolean;
  v_import   boolean;
  v_money    boolean;
  v_issue    boolean;
  v_state    text := new.invoice_state;
begin
  -- Service role, cron, migrations. Already trusted.
  if auth.uid() is null then return new; end if;

  v_send     := public.auth_has_permission('invoice.send', v_co);
  v_void     := public.auth_has_permission('invoice.void', v_co);
  v_writeoff := public.auth_has_permission('invoice.write_off', v_co);
  v_billing  := public.auth_has_permission('billing.configure', v_co);
  v_terms    := public.auth_has_permission('payments.terms_edit', v_co);
  v_import   := public.auth_has_permission('config.import_data', v_co);

  -- Issuing: send it, configure billing, or carry in history as a legacy import.
  v_issue := v_send or v_billing or (v_import and v_legacy);
  -- Moving money against an invoice. Void and write-off are included because
  -- both legitimately re-state the balance on their way through.
  v_money := public.auth_has_permission('payment.record', v_co)
          or public.auth_has_permission('payment.charge_card', v_co)
          or public.auth_has_permission('ar.late_fee_apply', v_co)
          or v_void or v_writeoff or v_billing;

  -- ── the number, the sequence, posted ────────────────────────────────────
  if ((v_ins and new.invoice_number is not null)     or (not v_ins and new.invoice_number     is distinct from old.invoice_number))
  or ((v_ins and new.invoice_sequence is not null)   or (not v_ins and new.invoice_sequence   is distinct from old.invoice_sequence))
  or ((v_ins and coalesce(new.posted, false))        or (not v_ins and new.posted             is distinct from old.posted)) then
    if not v_issue then
      raise exception 'You may not issue or post an invoice.' using errcode = 'insufficient_privilege';
    end if;
  end if;

  if (v_ins and new.invoice_sent_at is not null) or (not v_ins and new.invoice_sent_at is distinct from old.invoice_sent_at) then
    if not v_send then
      raise exception 'You may not send an invoice.' using errcode = 'insufficient_privilege';
    end if;
  end if;

  -- ── voiding ─────────────────────────────────────────────────────────────
  if ((v_ins and new.voided_at is not null)                 or (not v_ins and new.voided_at                 is distinct from old.voided_at))
  or ((v_ins and new.supersedes_invoice_number is not null) or (not v_ins and new.supersedes_invoice_number is distinct from old.supersedes_invoice_number))
  or ((v_ins and new.superseded_by_order_id is not null)    or (not v_ins and new.superseded_by_order_id    is distinct from old.superseded_by_order_id)) then
    if not v_void then
      raise exception 'You may not void an invoice.' using errcode = 'insufficient_privilege';
    end if;
  end if;

  -- ── writing off ─────────────────────────────────────────────────────────
  if (v_ins and new.written_off_at is not null) or (not v_ins and new.written_off_at is distinct from old.written_off_at) then
    if not v_writeoff then
      raise exception 'You may not write off an invoice.' using errcode = 'insufficient_privilege';
    end if;
  end if;

  -- ── money landing on it ─────────────────────────────────────────────────
  if (v_ins and new.paid_at is not null) or (not v_ins and new.paid_at is distinct from old.paid_at) then
    if not v_money then
      raise exception 'You may not record payment against an invoice.' using errcode = 'insufficient_privilege';
    end if;
  end if;

  -- ── terms and the date it falls due ─────────────────────────────────────
  if ((v_ins and new.due_date is not null)      or (not v_ins and new.due_date      is distinct from old.due_date))
  or ((v_ins and new.payment_terms is not null) or (not v_ins and new.payment_terms is distinct from old.payment_terms)) then
    if not (v_terms or v_send or v_billing) then
      raise exception 'You may not change an invoice''s terms or due date.' using errcode = 'insufficient_privilege';
    end if;
  end if;

  -- ── excluding a row from ageing ─────────────────────────────────────────
  if (v_ins and coalesce(new.aging_excluded, false)) or (not v_ins and new.aging_excluded is distinct from old.aging_excluded) then
    if not (v_billing or (v_import and v_legacy)) then
      raise exception 'You may not exclude an invoice from ageing.' using errcode = 'insufficient_privilege';
    end if;
  end if;

  -- ── the state itself, judged by where it is going ───────────────────────
  if (v_ins and v_state is not null) or (not v_ins and new.invoice_state is distinct from old.invoice_state) then
    if v_state = 'void' then
      if not v_void then
        raise exception 'You may not void an invoice.' using errcode = 'insufficient_privilege';
      end if;
    elsif v_state = 'written_off' then
      if not v_writeoff then
        raise exception 'You may not write off an invoice.' using errcode = 'insufficient_privilege';
      end if;
    elsif v_state in ('draft', 'open') then
      if not v_issue then
        raise exception 'You may not issue an invoice.' using errcode = 'insufficient_privilege';
      end if;
    elsif v_state in ('paid', 'partial', 'overdue') then
      if not v_money then
        raise exception 'You may not re-state an invoice''s balance.' using errcode = 'insufficient_privilege';
      end if;
    elsif v_state is null then
      -- Clearing the state unwinds an issued invoice.
      if not v_void then
        raise exception 'You may not clear an invoice''s state.' using errcode = 'insufficient_privilege';
      end if;
    end if;
  end if;

  -- ── what the gateway says happened ──────────────────────────────────────
  -- Written only by the storefront checkout and the ActivityPay webhook, both on
  -- the service role. A session has no business setting it at all.
  if (v_ins and new.payment_status is not null) or (not v_ins and new.payment_status is distinct from old.payment_status) then
    raise exception 'Payment status is set by the payment provider, not from the app.'
      using errcode = 'insufficient_privilege';
  end if;

  return new;
end;
$$;

comment on function public.guard_order_invoice_columns() is
  'The invoice and payment fields on an order each ask for the permission their own action asks for. The row policy stays tenancy-only because every ordinary order write would otherwise need an invoice key. Callers with no JWT (service role, cron) are exempt.';

drop trigger if exists zzz_guard_order_invoice_columns on public.orders;
create trigger zzz_guard_order_invoice_columns
  before insert or update on public.orders
  for each row execute function public.guard_order_invoice_columns();

commit;
