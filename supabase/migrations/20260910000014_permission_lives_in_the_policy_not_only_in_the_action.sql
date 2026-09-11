-- Permission lives in the policy, not only in the action. (M11, money and identity.)
--
-- The audit's systemic finding: every one of the 156 policied tables carries a
-- tenancy-only `FOR ALL` policy and `authenticated` holds table-wide
-- INSERT/UPDATE/DELETE, so role and plan are enforced ONLY inside Next.js server
-- actions. Over PostgREST, any team member with a session could approve their own
-- merchant application, rewrite the invoice counter, the late-fee policy and the
-- tax tables, insert payments and allocations, delete payments, and plant
-- transactions. `auth_has_permission()` exists and is used by exactly the newest
-- tables (terminal, recall, pack); everything older was left to the app.
--
-- This is the money and identity half. Each table's write policies now name the
-- SAME key the server action already requires, taken from a read of every write
-- path in both repos. Reads stay tenancy-only: nothing here changes who can SEE
-- their own company's data.
--
--   company_kyc, _beneficial_owners, _documents   payments.merchant_onboard
--   billing_settings                              billing.configure OR tax.configure
--   payment_terms                                 billing.configure
--   tax_rate, tax_rule, tax_jurisdiction          tax.configure
--   invoice_payments            insert/delete     payment.record
--                               update            invoice.void
--   invoice_payment_allocations                   payment.record
--   credit_memos                                  invoice.void
--   payment_transactions        insert/update     payment.charge_card
--   payouts, chargebacks, statements              no write policy at all
--
-- service_role holds BYPASSRLS (checked), so every webhook, cron and
-- admin-client path is untouched by all of this. The storefront checkout and the
-- ActivityPay webhook both run there.
--
-- ── The two companion changes, without which this WOULD break real users ──
--
-- 1. The invoice counters. allocate_invoice_number, allocate_credit_memo_number
--    and sync_invoice_next_seq UPDATE billing_settings, and they run under
--    invoice.send / invoice.void / ar.late_fee_apply / config.import_data —
--    keys a MANAGER holds without holding billing.configure. Left as INVOKER,
--    a manager finalising an invoice would hit "no billing settings for company
--    … check your access" and the invoice would not issue. They become
--    SECURITY DEFINER with the tenancy test written out (they already scoped
--    their provisioning INSERT to auth_company_ids(); as definer the UPDATE
--    needs saying too, because RLS no longer stands behind it).
--
-- 2. company_kyc.status. The form legitimately writes 'not_started' and
--    'submitted', and re-sends 'approved' unchanged when an approved merchant
--    edits their details. Approval itself happens outside the app. A trigger
--    holds that line: a caller with a JWT may not move status to approved,
--    under_review or rejected, but an unchanged value always passes.
--
-- Not here, and why: `orders` gets the same treatment through a COLUMN trigger
-- in the next migration — its invoice fields need gating but a row policy keyed
-- on an invoice permission would refuse every ordinary order edit. The roast
-- tables follow after that.
--
-- Prod today: 0 rows any of these would have refused.

begin;

-- ═══ 1. the invoice counters keep working for the people who issue invoices ═══
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
  -- Definer from 20260910000014: the counter must bump for a manager holding
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

    exit when not exists (
      select 1 from public.orders
       where company_id = p_company_id
         and invoice_number = v_candidate
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

create or replace function public.allocate_credit_memo_number(p_company_id text)
returns table(credit_memo_sequence bigint, credit_memo_number text)
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_seq    bigint;
  v_prefix text;
  v_pad    integer;
  v_mode   text;
begin
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
$function$;

create or replace function public.sync_invoice_next_seq(p_company_id text)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_next bigint;
begin
  if auth.uid() is not null and p_company_id not in (select public.auth_company_ids()) then
    raise exception 'not authorized for company %', p_company_id;
  end if;

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
$function$;

-- ═══ 2. the policies ═══════════════════════════════════════════════════════
-- One shape per table: read by tenancy, write by tenancy AND the key the action
-- already asks for. A null key means no write policy for `authenticated` at all
-- — nothing in either repo writes those three from a user session.
do $$
declare
  r record;
  p record;
  v_tenancy constant text := 'company_id in (select public.auth_company_ids())';
  v_ins text; v_upd text; v_del text;
  -- 'a|b' becomes "has(a) or has(b)" — one key for most tables, two where the
  -- app legitimately uses either (billing_settings is written under
  -- billing.configure by Settings and under tax.configure by the tax form).
begin
  for r in
    select * from (values
      ('company_kyc',                 'payments.merchant_onboard', 'payments.merchant_onboard', 'payments.merchant_onboard'),
      ('company_kyc_beneficial_owners','payments.merchant_onboard','payments.merchant_onboard', 'payments.merchant_onboard'),
      ('company_kyc_documents',       'payments.merchant_onboard', 'payments.merchant_onboard', 'payments.merchant_onboard'),
      ('billing_settings',            'billing.configure|tax.configure', 'billing.configure|tax.configure', 'billing.configure|tax.configure'),
      ('tax_rate',                    'tax.configure',             'tax.configure',             'tax.configure'),
      ('tax_rule',                    'tax.configure',             'tax.configure',             'tax.configure'),
      ('invoice_payments',            'payment.record',            'invoice.void',              'payment.record'),
      ('invoice_payment_allocations', 'payment.record',            'payment.record',            'payment.record'),
      ('credit_memos',                'invoice.void',              'invoice.void',              'invoice.void'),
      ('payment_transactions',        'payment.charge_card',       'payment.charge_card',       null::text),
      ('payouts',                     null::text,                  null::text,                  null::text),
      ('chargebacks',                 null::text,                  null::text,                  null::text),
      ('statements',                  null::text,                  null::text,                  null::text)
    ) as t(tbl, ins_key, upd_key, del_key)
  loop
    -- Drop EVERY existing policy on the table, not a guessed list of names.
    -- tax_rate and tax_rule call theirs tax_rate_all / tax_rule_all, and a
    -- surviving permissive FOR ALL policy would be OR'd with the new ones —
    -- which would leave the key optional and this whole migration decorative.
    for p in select policyname from pg_policies
              where schemaname = 'public' and tablename = r.tbl
    loop
      execute format('drop policy if exists %I on public.%I', p.policyname, r.tbl);
    end loop;

    execute format('create policy %I on public.%I for select to authenticated using (%s)',
                   r.tbl || '_read', r.tbl, v_tenancy);

    -- 'a|b' becomes "has(a) or has(b)" — one key for most tables, two where the
    -- app legitimately writes under either (billing_settings is written under
    -- billing.configure by Settings and under tax.configure by the tax form).
    select string_agg(format('public.auth_has_permission(%L, company_id)', k), ' or ')
      into v_ins from unnest(string_to_array(coalesce(r.ins_key, ''), '|')) k where k <> '';
    select string_agg(format('public.auth_has_permission(%L, company_id)', k), ' or ')
      into v_upd from unnest(string_to_array(coalesce(r.upd_key, ''), '|')) k where k <> '';
    select string_agg(format('public.auth_has_permission(%L, company_id)', k), ' or ')
      into v_del from unnest(string_to_array(coalesce(r.del_key, ''), '|')) k where k <> '';

    if v_ins is not null then
      execute format('create policy %I on public.%I for insert to authenticated with check (%s and (%s))',
                     r.tbl || '_insert', r.tbl, v_tenancy, v_ins);
    end if;
    if v_upd is not null then
      execute format('create policy %I on public.%I for update to authenticated using (%s and (%s)) with check (%s and (%s))',
                     r.tbl || '_update', r.tbl, v_tenancy, v_upd, v_tenancy, v_upd);
    end if;
    if v_del is not null then
      execute format('create policy %I on public.%I for delete to authenticated using (%s and (%s))',
                     r.tbl || '_delete', r.tbl, v_tenancy, v_del);
    end if;
  end loop;
end $$;

-- payment_terms keeps its own four policies (globals are readable, tenant rows
-- are writable) — only the key is added.
drop policy if exists payment_terms_insert on public.payment_terms;
drop policy if exists payment_terms_update on public.payment_terms;
drop policy if exists payment_terms_delete on public.payment_terms;

create policy payment_terms_insert on public.payment_terms
  for insert to authenticated
  with check (company_id is not null
              and company_id in (select public.auth_company_ids())
              and public.auth_has_permission('billing.configure', company_id));

create policy payment_terms_update on public.payment_terms
  for update to authenticated
  using      (company_id is not null
              and company_id in (select public.auth_company_ids())
              and public.auth_has_permission('billing.configure', company_id))
  with check (company_id is not null
              and company_id in (select public.auth_company_ids())
              and public.auth_has_permission('billing.configure', company_id));

create policy payment_terms_delete on public.payment_terms
  for delete to authenticated
  using (company_id is not null
         and company_id in (select public.auth_company_ids())
         and public.auth_has_permission('billing.configure', company_id));

-- tax_jurisdiction: the seeded globals (company_id is null) stay readable by
-- everyone and writable by nobody.
drop policy if exists tax_jurisdiction_write on public.tax_jurisdiction;
create policy tax_jurisdiction_write on public.tax_jurisdiction
  for all to authenticated
  using      (company_id is not null
              and company_id in (select public.auth_company_ids())
              and public.auth_has_permission('tax.configure', company_id))
  with check (company_id is not null
              and company_id in (select public.auth_company_ids())
              and public.auth_has_permission('tax.configure', company_id));

-- ═══ 3. approving your own merchant application ════════════════════════════
create or replace function public.guard_kyc_status()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- No JWT: the reviewer's own path (service role) sets approved / rejected.
  if auth.uid() is null then return new; end if;

  -- An unchanged value always passes: the onboarding form re-sends the current
  -- status when an already-approved merchant edits their details.
  if tg_op = 'UPDATE' and new.status is not distinct from old.status then
    return new;
  end if;

  if new.status is distinct from 'not_started' and new.status is distinct from 'submitted' then
    raise exception 'Only STRATA can approve or decline a merchant application.'
      using errcode = 'insufficient_privilege';
  end if;

  return new;
end;
$$;

drop trigger if exists zz_guard_kyc_status on public.company_kyc;
create trigger zz_guard_kyc_status
  before insert or update of status on public.company_kyc
  for each row execute function public.guard_kyc_status();

comment on function public.guard_kyc_status() is
  'A merchant application may be submitted from the app but never approved there — status approved/under_review/rejected is the service role''s to set. An unchanged value always passes.';

-- ═══ 4. nobody merges a customer by PATCHing a column ══════════════════════
-- customers.merge_into_id fires trg_merge_customer, which remaps every order,
-- line, contact, note and task onto another customer and deactivates this one.
-- No application path writes it from a user client; updateCustomer passes the
-- browser's fields straight through, so it was reachable. The grant is rebuilt
-- without it (a column grant is per ROLE, so the rest must be re-granted by
-- name — the lesson from 20260908000034).
do $$
declare cols text;
begin
  select string_agg(quote_ident(column_name), ', ' order by ordinal_position)
    into cols
    from information_schema.columns
   where table_schema = 'public' and table_name = 'customers'
     and column_name <> 'merge_into_id'
     and is_generated = 'NEVER';
  execute 'revoke update on public.customers from authenticated';
  execute format('grant update (%s) on public.customers to authenticated', cols);
end $$;

commit;
