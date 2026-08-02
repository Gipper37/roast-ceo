-- Invoicing stops being a ceremony you have to perform first.
--
-- 🔴 WHAT WAS WRONG. Issuing a STRATA invoice required a "cutover": answer a
-- question in Settings (or inside the QuickBooks import), which wrote
-- billing_settings.invoice_of_record='strata'. Until then allocate_invoice_number
-- RAISED "company is Mode B — QuickBooks is the biller". Three things followed
-- from that, all bad:
--
--   · A roaster on a plan that INCLUDES invoicing was told they could not
--     invoice, and had to find a settings page to grant themselves something
--     they had already paid for.
--   · The import flow asked "should STRATA become your invoice of record?" —
--     including of companies that had already switched, which is a question with
--     no honest answer.
--   · It implied importing and invoicing were one decision. They are not. You
--     can import QuickBooks history before your first STRATA invoice, after your
--     five hundredth, or never.
--
-- THE RULE NOW: entitlement decides. Plan + permission gate invoicing (both
-- enforced in the app); this function no longer asks whether a ritual was
-- completed. A missing billing_settings row means "never configured", not "opted
-- out", so it is created on first use — with numbering already continuing from
-- the highest invoice number in the company, which is exactly what the cutover
-- form used to ask a human to type in.
--
-- invoice_of_record SURVIVES as a real opt-out. A row that explicitly says
-- 'quickbooks' still blocks, because that is a roaster who has said QuickBooks
-- is their biller and meant it. Nobody is in that state today (verified in prod:
-- of five companies, one row exists and it says 'strata'), so this changes
-- nothing retroactively — it only stops the other four being asked a question
-- they should never have seen.

begin;

-- ── Invoice numbers ──────────────────────────────────────────────────────────
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
  -- Provision on first use. Numbering starts one past the highest number already
  -- in the company, so a roaster who imported QuickBooks history first carries on
  -- from it instead of colliding — the single question the cutover form existed
  -- to ask, answered from the data.
  --
  -- Scoped to auth_company_ids() so this can never mint a settings row for a
  -- company the caller does not belong to. RLS covers the same ground; being
  -- explicit here means the INSERT reads as safe without going to look.
  insert into public.billing_settings
    (company_id, invoice_of_record, invoice_next_seq, invoice_prefix, invoice_pad_width, credit_memo_prefix)
  select p_company_id, 'strata',
         greatest(1, public.max_numeric_invoice_number(p_company_id) + 1),
         '', 6, 'CM-'
   where not exists (select 1 from public.billing_settings where company_id = p_company_id)
     and p_company_id in (select auth_company_ids())
  on conflict (company_id) do nothing;

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
      raise exception 'no billing settings for company % and none could be created — check your access', p_company_id;
    end if;
    -- Only an EXPLICIT opt-out blocks. Absence is not refusal.
    if v_mode = 'quickbooks' then
      raise exception 'company % has QuickBooks set as its invoice of record — turn that off in Settings to invoice from STRATA', p_company_id;
    end if;

    v_candidate := coalesce(v_prefix, '') || lpad(v_seq::text, coalesce(v_pad, 6), '0');

    -- Exact-match lookup on orders_company_invoice_number_uidx: indexed, so the
    -- normal no-collision case costs one index probe.
    exit when not exists (
      select 1 from public.orders
       where company_id = p_company_id
         and invoice_number = v_candidate
    );

    -- Taken. On the FIRST collision, jump past every all-numeric number in use
    -- rather than walking them one probe at a time.
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
  'Allocate the next STRATA invoice number, skipping any number already on orders. Provisions billing_settings on first use (numbering continues from the highest number in the company). Blocks only when invoice_of_record is explicitly ''quickbooks''.';

revoke all on function public.allocate_invoice_number(text) from public, anon;
grant execute on function public.allocate_invoice_number(text) to authenticated;

-- ── Credit-memo numbers ──────────────────────────────────────────────────────
-- Same rule. A credit memo is how you correct an invoice, so anyone who can
-- issue one must be able to correct it — gating them differently would strand a
-- roaster with an invoice they cannot fix.
create or replace function public.allocate_credit_memo_number(p_company_id text)
  returns table(credit_memo_sequence bigint, credit_memo_number text)
  language plpgsql as $$
declare
  v_seq    bigint;
  v_prefix text;
  v_pad    integer;
  v_mode   text;
begin
  insert into public.billing_settings
    (company_id, invoice_of_record, invoice_next_seq, invoice_prefix, invoice_pad_width, credit_memo_prefix)
  select p_company_id, 'strata',
         greatest(1, public.max_numeric_invoice_number(p_company_id) + 1),
         '', 6, 'CM-'
   where not exists (select 1 from public.billing_settings where company_id = p_company_id)
     and p_company_id in (select auth_company_ids())
  on conflict (company_id) do nothing;

  update public.billing_settings
     set credit_memo_next_seq = credit_memo_next_seq + 1,
         updated_at           = now()
   where company_id = p_company_id
  returning credit_memo_next_seq - 1, credit_memo_prefix, invoice_pad_width, invoice_of_record
       into v_seq, v_prefix, v_pad, v_mode;

  if not found then
    raise exception 'no billing settings for company % and none could be created — check your access', p_company_id;
  end if;
  if v_mode = 'quickbooks' then
    raise exception 'company % has QuickBooks set as its invoice of record — turn that off in Settings to issue credit memos from STRATA', p_company_id;
  end if;

  credit_memo_sequence := v_seq;
  credit_memo_number   := coalesce(v_prefix, 'CM-') || lpad(v_seq::text, coalesce(v_pad, 6), '0');
  return next;
end;
$$;

comment on function public.allocate_credit_memo_number(text) is
  'Allocate the next credit-memo number. Provisions billing_settings on first use. Blocks only when invoice_of_record is explicitly ''quickbooks''.';

revoke all on function public.allocate_credit_memo_number(text) from public, anon;
grant execute on function public.allocate_credit_memo_number(text) to authenticated;

commit;

notify pgrst, 'reload schema';
