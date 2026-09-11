-- The invoice numberer cannot see past its own name.
--
-- allocate_invoice_number RETURNS TABLE(invoice_sequence bigint, invoice_number
-- text). Those are PL/pgSQL variables. Its collision check reads
--
--     exit when not exists (
--       select 1 from public.orders
--        where company_id = p_company_id
--          and invoice_number = v_candidate   -- <= orders.invoice_number, or the OUT param?
--     );
--
-- and PL/pgSQL's default variable_conflict is `error`, so the statement raises
-- "column reference invoice_number is ambiguous" the first time the loop reaches
-- it — which is every call. The function is unusable for any company whose
-- invoice of record is STRATA. A company on QuickBooks raises earlier, which is
-- why this went unseen.
--
-- Introduced by 20260801000001_invoice_number_continuation.sql, which added the
-- collision loop. It is on prod. Maui Coffee Roasters is in STRATA mode, and the
-- only two invoices STRATA ever issued for them are dated 2026-07-06 — before
-- that migration. 73 invoiceable orders have been created since July with no
-- invoice number, and nothing in server_error_events records why: the action
-- returns { ok: false } rather than throwing, so the failure reached the
-- operator as a toast and went nowhere else.
--
-- Found by calling the function, not by reading it: the audit's two passes and
-- its adversarial pass all read this file and none of them ran it.
--
-- One alias. Nothing else about the function changes.

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
  -- Definer since 20260910000014: the counter must bump for a manager holding
  -- invoice.send but not billing.configure. RLS no longer stands behind this,
  -- so the tenancy test is written out. Service role and cron carry no JWT.
  if auth.uid() is not null and p_company_id not in (select public.auth_company_ids()) then
    raise exception 'That company is not yours.' using errcode = 'insufficient_privilege';
  end if;

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

    -- 🔴 `o.` is load-bearing. Unqualified, `invoice_number` matches this
    -- function's OUT parameter as well as the column, and PL/pgSQL refuses to
    -- guess. Exact-match lookup on orders_company_invoice_number_uidx: indexed,
    -- so the normal no-collision case costs one index probe.
    exit when not exists (
      select 1 from public.orders o
       where o.company_id = p_company_id
         and o.invoice_number = v_candidate
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
$function$;

commit;
