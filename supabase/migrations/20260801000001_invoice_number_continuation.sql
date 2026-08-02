-- STRATA never reissues an invoice number that already exists.
--
-- 🔴 THE BUG THIS FIXES, with real numbers. MCR cut over to STRATA invoicing on
-- 2026-07-06 with invoice_next_seq = 104544 (their QuickBooks max was 104543) and
-- an EMPTY invoice_prefix. They are now importing more QuickBooks history whose
-- invoice numbers run up to 104698. Nothing bumps the counter on an import —
-- max_numeric_invoice_number() only ever PREFILLED the cutover form, and
-- commit_cutover cannot re-run — so after the import STRATA still believes the
-- next number is 104544, which by then is one of the imported invoices.
--
-- With an empty prefix the collision is exact, and it does not self-heal:
-- allocate_invoice_number bumps and returns inside the CALLER's transaction, so
-- the unique violation on orders_company_invoice_number_uidx rolls the bump back
-- too. The next attempt allocates 104544 again. Invoice numbering would be
-- permanently stuck until someone raised the counter by hand.
--
-- THE RULE, as the operator would state it: the next invoice number is one past
-- the highest number already in use — however it got there, import or not, with
-- no one having to think about it.
--
-- Two parts:
--   1. sync_invoice_next_seq() — raise the counter past everything already in
--      use. Idempotent, and it can only ever RAISE: lowering a counter is how you
--      reissue a number that a customer has already been sent.
--   2. allocate_invoice_number() — skip any number already taken. This is the
--      correctness guarantee, and it covers every path (import, manual edit,
--      restored backup), not just the import we know about.
--
-- Credit memos deliberately do NOT get this. They have their own sequence in
-- their own table (credit_memos.credit_memo_number, prefix 'CM-'), and imported
-- QB credit memos land in `orders` claiming a bare numeric invoice_number, so
-- they collide with INVOICE numbering, not with credit-memo numbering — which
-- part 2 already covers by checking orders.invoice_number.

begin;

-- ── 1. Raise the counter past every number already in use ────────────────────
create or replace function public.sync_invoice_next_seq(p_company_id text)
returns bigint
language plpgsql
as $$
declare
  v_next bigint;
begin
  if p_company_id not in (select auth_company_ids()) then
    raise exception 'not authorized for company %', p_company_id;
  end if;

  -- GREATEST, never a bare assignment: this must not walk the counter BACKWARDS
  -- if a company's highest imported number happens to be below where STRATA has
  -- already issued to.
  update public.billing_settings
     set invoice_next_seq = greatest(
           invoice_next_seq,
           public.max_numeric_invoice_number(p_company_id) + 1
         ),
         updated_at = now()
   where company_id = p_company_id
  returning invoice_next_seq into v_next;

  if not found then
    raise exception 'billing_settings row missing for company %', p_company_id;
  end if;

  return v_next;
end;
$$;

comment on function public.sync_invoice_next_seq(text) is
  'Raise billing_settings.invoice_next_seq past the highest all-numeric invoice_number already in use. Idempotent; only ever raises. Called after a history import so the counter (and the number shown in Settings) reflects reality.';

revoke all on function public.sync_invoice_next_seq(text) from public, anon;
grant execute on function public.sync_invoice_next_seq(text) to authenticated;

-- ── 2. Never hand out a number that is already taken ─────────────────────────
-- Unchanged from 20260705000002 except for the skip loop: same gap-free
-- ON CONFLICT row-lock, same Mode-B guard, same SECURITY INVOKER so RLS scopes
-- each caller to their own company.
create or replace function public.allocate_invoice_number(p_company_id text)
  returns table(invoice_sequence bigint, invoice_number text)
  language plpgsql as $$
declare
  v_seq       bigint;
  v_prefix    text;
  v_pad       integer;
  v_mode      text;
  v_candidate text;
  v_jumped    boolean := false;
  v_guard     integer := 0;
begin
  loop
    -- A bound, so a pathological data set fails loudly instead of spinning.
    v_guard := v_guard + 1;
    if v_guard > 1000 then
      raise exception 'no free invoice number for company % after 1000 attempts (last tried %)',
        p_company_id, v_candidate;
    end if;

    update public.billing_settings
       set invoice_next_seq = invoice_next_seq + 1,
           updated_at       = now()
     where company_id = p_company_id
    returning invoice_next_seq - 1, invoice_prefix, invoice_pad_width, invoice_of_record
         into v_seq, v_prefix, v_pad, v_mode;

    if not found then
      raise exception 'billing_settings row missing for company % — configure invoice-of-record before invoicing', p_company_id;
    end if;
    if v_mode <> 'strata' then
      raise exception 'company % is Mode B (invoice_of_record=%) — QuickBooks is the biller, no STRATA number allocated', p_company_id, v_mode;
    end if;

    v_candidate := coalesce(v_prefix, '') || lpad(v_seq::text, coalesce(v_pad, 6), '0');

    -- Exact-match lookup on orders_company_invoice_number_uidx: indexed, so the
    -- normal no-collision case costs one index probe.
    exit when not exists (
      select 1 from public.orders
       where company_id = p_company_id
         and invoice_number = v_candidate
    );

    -- Taken. On the FIRST collision, jump the counter past every all-numeric
    -- number in use rather than walking 155 of them one probe at a time. This is
    -- an optimisation only — the loop is what guarantees correctness, and it
    -- still works when the jump cannot help (a prefixed scheme, where
    -- max_numeric_invoice_number sees nothing to compare against).
    if not v_jumped then
      v_jumped := true;
      update public.billing_settings
         set invoice_next_seq = greatest(
               invoice_next_seq,
               public.max_numeric_invoice_number(p_company_id) + 1
             )
       where company_id = p_company_id;
    end if;
  end loop;

  invoice_sequence := v_seq;
  invoice_number   := v_candidate;
  return next;
end;
$$;

comment on function public.allocate_invoice_number(text) is
  'Allocate the next STRATA invoice number for a company, skipping any number already present on orders (imported QuickBooks history, restored rows). Gap-free row-lock counter; Mode A only.';

revoke all on function public.allocate_invoice_number(text) from public, anon;
grant execute on function public.allocate_invoice_number(text) to authenticated;

commit;

notify pgrst, 'reload schema';
