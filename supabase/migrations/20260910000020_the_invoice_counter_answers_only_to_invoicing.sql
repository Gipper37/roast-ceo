-- The invoice counter answers only to invoicing.
--
-- 20260910000019 gave allocate_invoice_number the key list
-- {invoice.send, billing.configure, config.import_data}. The import key does not
-- belong: nothing in the import path allocates a STRATA number. The QuickBooks
-- importer inserts history rows carrying their own QB number
-- (qbImportActions.ts:1659) and advances the counter afterwards through
-- sync_invoice_next_seq, which keeps config.import_data. The only caller of
-- allocate_invoice_number anywhere — app or database — is finalize_invoice, and
-- its only caller is finalizeAndSendInvoice under invoice.send.
--
-- Left in by me, and it showed: a roastmaster (who holds config.import_data on
-- Enterprise) got past the guard on staging and was stopped only by the
-- unrelated QuickBooks-mode check.

begin;

create or replace function public.allocate_invoice_number(p_company_id text)
returns table(invoice_sequence bigint, invoice_number text)
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_seq       bigint;
  v_prefix    text;
  v_pad       integer;
  v_mode      text;
  v_candidate text;
  v_jumped    boolean := false;
  v_guard     integer := 0;
begin
  -- Issuing an invoice, or configuring the billing that provisions numbering.
  perform public.guard_counter_caller(p_company_id, array['invoice.send', 'billing.configure']);

  insert into public.billing_settings
    (company_id, invoice_of_record, invoice_next_seq, invoice_prefix, invoice_pad_width, credit_memo_prefix)
  select p_company_id, 'strata',
         greatest(1, public.max_numeric_invoice_number(p_company_id) + 1),
         '', 6, 'CM-'
   where not exists (select 1 from public.billing_settings where company_id = p_company_id)
  on conflict (company_id) do nothing;

  loop
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
    if v_mode = 'quickbooks' then
      raise exception 'company % has QuickBooks set as its invoice of record — turn that off in Settings to invoice from STRATA', p_company_id;
    end if;

    v_candidate := coalesce(v_prefix, '') || lpad(v_seq::text, coalesce(v_pad, 6), '0');

    -- 🔴 `o.` is load-bearing (20260910000015).
    exit when not exists (
      select 1 from public.orders o
       where o.company_id = p_company_id
         and o.invoice_number = v_candidate
    );

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
$function$;

commit;
