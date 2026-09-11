-- What the adversarial pass found in the permission policies.
--
-- Twelve claims against 20260910000014-17 survived independent verification.
-- Four of them are regressions I introduced; the rest are gaps in the same
-- work. All of it is closed here.
--
-- 1. 🔴 I WIDENED THE FACILITY BOUNDARY. roast_events and roast_temp_nodes were
--    scoped by auth_facility_ids() — the facility on your own team row — for
--    every command. …0017 replaced the write side with a FOR ALL policy using
--    auth_roast_log_facility_ids(), which returns every facility of every
--    company you may log roasts for. A permissive FOR ALL policy's USING clause
--    is OR'd into SELECT as well, so one facility could read, edit and delete
--    another facility's curves. Measured on staging: own scope
--    {demo-kailua-roastery}, new scope {demo-kailua-roastery, uitest-fac-2}.
--    Now: the helper intersects with the caller's own facilities, and the write
--    policies are per-command so their USING never reaches SELECT.
--
-- 2. roast.delete_completed was bypassed. `roast_log_write` was FOR ALL on
--    roast.log, so DELETE asked only for roast.log — and roast.delete_completed
--    is a key the product explicitly withholds from roastmaster. The argument in
--    …0017 for not splitting on "completed" was about UPDATE (an
--    assistant_roaster's grace-period restart); DELETE inherited it by accident.
--
-- 3. is_legacy_import was attacker-controlled. guard_order_invoice_columns reads
--    the flag off the INCOMING row to decide whether config.import_data counts
--    as permission to issue — but the flag itself was ungated, so a holder of
--    config.import_data could set it true and issue, post, number and
--    age-exclude a live invoice in one statement. The carve-out now reads the
--    STORED value on an update, and setting the flag needs config.import_data
--    and is only possible as the row is created.
--
-- 4. The three definer counters skipped the gate the same migration installed.
--    Made SECURITY DEFINER in …0014 so a manager could issue an invoice, they
--    kept only a tenancy test — and they are PostgREST RPCs, so any member of
--    the tenant could bump invoice_next_seq or credit_memo_next_seq at will.
--    They now ask for the permission their own use implies.
--
-- 5. 🔴 EVERY TRIALING TENANT WOULD HAVE BEEN LOCKED OUT OF MONEY. The app
--    resolves a subscription whose status is 'trialing' to the enterprise plan
--    (lib/permissions/server.ts) — that is what a free trial IS. auth_has_
--    permission joined plan_permissions on the RAW plan_id with no such branch,
--    so from the moment …0014 landed, a trialing tenant would pass
--    requirePermission and then be refused by RLS on every plan-gated key:
--    billing, tax, payments, invoicing. company-signup puts every new tenant on
--    a 30-day trial, so this was every new customer. The function now reads a
--    trial the way the app does.
--
-- 6. An approved merchant could never save the onboarding form again.
--    guard_kyc_status exempted an unchanged status only on tg_op='UPDATE', but
--    the only writer is an upsert and Postgres fires the BEFORE INSERT trigger
--    before resolving the conflict — so the re-sent 'approved' hit the raise.
--    It now compares against the stored row, which is right for both paths.
--
-- Not fixed here, deliberately: an accounting_admin correcting a green cost no
-- longer revalues roast COGS, because that chain runs SECURITY INVOKER inside
-- their transaction and they do not hold roast.log. Converting eight functions
-- to definer is its own change with its own testing; recorded instead.

begin;

-- ═══ 1. the facility boundary, restored ════════════════════════════════════
create or replace function public.auth_roast_log_facility_ids()
returns setof text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- YOUR facilities — the ones on your own team rows — and only where you may
  -- log a roast. Never every facility of the company: that is what the first
  -- version did, and it handed one facility another facility's curves.
  select t.facility_id
    from public.team t
   where t.auth_user_id = auth.uid()
     and coalesce(t.is_active, true)
     and t.facility_id is not null
     and exists (select 1 from public.facilities f
                  where f.facility_id = t.facility_id and f.company_id = t.company_id)
     and public.auth_has_permission('roast.log', t.company_id);
$$;

comment on function public.auth_roast_log_facility_ids() is
  'The caller''s OWN facilities in which they may log a roast. Scoped like auth_facility_ids(), then filtered by the permission.';

-- Per-command policies. A permissive FOR ALL policy's USING is OR'd into SELECT,
-- which is how the write scope leaked into the read scope.
do $$
declare t text;
begin
  foreach t in array array['roast_events', 'roast_temp_nodes'] loop
    execute format('drop policy if exists %I on public.%I', t || '_write', t);
    execute format(
      'create policy %I on public.%I for insert to authenticated '
      'with check (facility_id in (select public.auth_roast_log_facility_ids()))', t || '_insert', t);
    execute format(
      'create policy %I on public.%I for update to authenticated '
      'using (facility_id in (select public.auth_roast_log_facility_ids())) '
      'with check (facility_id in (select public.auth_roast_log_facility_ids()))', t || '_update', t);
    execute format(
      'create policy %I on public.%I for delete to authenticated '
      'using (facility_id in (select public.auth_roast_log_facility_ids()))', t || '_delete', t);
  end loop;

  foreach t in array array['roast_sessions', 'roast_smartroast_log'] loop
    execute format('drop policy if exists %I on public.%I', t || '_write', t);
    execute format(
      'create policy %I on public.%I for insert to authenticated '
      'with check (company_id in (select public.auth_roast_log_company_ids()))', t || '_insert', t);
    execute format(
      'create policy %I on public.%I for update to authenticated '
      'using (company_id in (select public.auth_roast_log_company_ids())) '
      'with check (company_id in (select public.auth_roast_log_company_ids()))', t || '_update', t);
    execute format(
      'create policy %I on public.%I for delete to authenticated '
      'using (company_id in (select public.auth_roast_log_company_ids()))', t || '_delete', t);
  end loop;
end $$;

-- ═══ 2. deleting a finished roast asks for the key that names it ═══════════
create or replace function public.auth_roast_delete_company_ids()
returns setof text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select t.company_id
    from public.team t
   where t.auth_user_id = auth.uid()
     and coalesce(t.is_active, true)
     and public.auth_has_permission('roast.delete_completed', t.company_id);
$$;

revoke all on function public.auth_roast_delete_company_ids() from public, anon;
grant execute on function public.auth_roast_delete_company_ids() to authenticated, service_role;

drop policy if exists roast_log_write on public.roast_log;
create policy roast_log_insert on public.roast_log
  for insert to authenticated
  with check (company_id in (select public.auth_roast_log_company_ids()));
create policy roast_log_update on public.roast_log
  for update to authenticated
  using      (company_id in (select public.auth_roast_log_company_ids()))
  with check (company_id in (select public.auth_roast_log_company_ids()));
create policy roast_log_delete on public.roast_log
  for delete to authenticated
  using (company_id in (select public.auth_roast_delete_company_ids()));

-- ═══ 3. a trial is the plan the app says it is ════════════════════════════
create or replace function public.auth_has_permission(p_permission_id text, p_company_id text default null)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
      from public.team t
      join public.role_permissions rp
        on rp.role_id = t.role and rp.permission_id = p_permission_id and rp.granted
      join public.permissions p
        on p.permission_id = p_permission_id
     where t.auth_user_id = auth.uid()
       and coalesce(t.is_active, true)
       and (p_company_id is null or t.company_id = p_company_id)
       and (
         not p.is_plan_gated
         or exists (
           select 1
             from public.company_subscription_status s
             join public.plan_permissions pp
               -- A trial IS the enterprise plan for as long as it lasts. The app
               -- has always resolved it that way (lib/permissions/server.ts);
               -- reading the raw plan_id here would have refused every plan-gated
               -- key to every tenant in their first 30 days — which is every new
               -- tenant company-signup creates.
               on pp.plan_id = (case when s.status = 'trialing' then 'enterprise' else s.plan_id end)
              and pp.permission_id = p_permission_id
              and pp.granted
            where s.company_id = t.company_id
         )
       )
       -- ── The terminal narrowing ───────────────────────────────────────────
       -- An ordinary login is unaffected. A TERMINAL login must have somebody
       -- PIN'd in, and that person's own role has to grant the key too.
       and (
         not coalesce(t.is_terminal, false)
         or exists (
           select 1
             from public.terminal_actor_session ses
             join public.team pinned
               on pinned.team_member_id = ses.team_member_id
             join public.role_permissions rp2
               on rp2.role_id = pinned.role
              and rp2.permission_id = p_permission_id
              and rp2.granted
            where ses.terminal_member_id = t.team_member_id
              and ses.ended_at is null
              and ses.expires_at > now()
              and coalesce(pinned.is_active, true)
         )
       )
  );
$$;

-- ═══ 4. the legacy-import carve-out is not the caller's to grant ══════════
create or replace function public.guard_order_invoice_columns()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_co       text := new.company_id;
  v_ins      boolean := (tg_op = 'INSERT');
  -- 🔴 The STORED flag on an update, never the incoming one. Reading NEW meant a
  -- caller could set is_legacy_import true and grant themselves the carve-out in
  -- the same statement.
  v_legacy   boolean := coalesce(case when v_ins then new.is_legacy_import else old.is_legacy_import end, false);
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
  if auth.uid() is null then return new; end if;

  v_send     := public.auth_has_permission('invoice.send', v_co);
  v_void     := public.auth_has_permission('invoice.void', v_co);
  v_writeoff := public.auth_has_permission('invoice.write_off', v_co);
  v_billing  := public.auth_has_permission('billing.configure', v_co);
  v_terms    := public.auth_has_permission('payments.terms_edit', v_co);
  v_import   := public.auth_has_permission('config.import_data', v_co);

  -- Marking a row as imported history is an import decision, and only ever as
  -- the row is written for the first time.
  if not v_ins and (new.is_legacy_import is distinct from old.is_legacy_import) then
    raise exception 'Whether an order is imported history is fixed when it is created.'
      using errcode = 'insufficient_privilege';
  end if;
  if v_ins and coalesce(new.is_legacy_import, false) and not v_import then
    raise exception 'You may not import invoice history.' using errcode = 'insufficient_privilege';
  end if;

  v_issue := v_send or v_billing or (v_import and v_legacy);
  v_money := public.auth_has_permission('payment.record', v_co)
          or public.auth_has_permission('payment.charge_card', v_co)
          or public.auth_has_permission('ar.late_fee_apply', v_co)
          or v_void or v_writeoff or v_billing;

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

  if ((v_ins and new.voided_at is not null)                 or (not v_ins and new.voided_at                 is distinct from old.voided_at))
  or ((v_ins and new.supersedes_invoice_number is not null) or (not v_ins and new.supersedes_invoice_number is distinct from old.supersedes_invoice_number))
  or ((v_ins and new.superseded_by_order_id is not null)    or (not v_ins and new.superseded_by_order_id    is distinct from old.superseded_by_order_id)) then
    if not v_void then
      raise exception 'You may not void an invoice.' using errcode = 'insufficient_privilege';
    end if;
  end if;

  if (v_ins and new.written_off_at is not null) or (not v_ins and new.written_off_at is distinct from old.written_off_at) then
    if not v_writeoff then
      raise exception 'You may not write off an invoice.' using errcode = 'insufficient_privilege';
    end if;
  end if;

  if (v_ins and new.paid_at is not null) or (not v_ins and new.paid_at is distinct from old.paid_at) then
    if not v_money then
      raise exception 'You may not record payment against an invoice.' using errcode = 'insufficient_privilege';
    end if;
  end if;

  if ((v_ins and new.due_date is not null)      or (not v_ins and new.due_date      is distinct from old.due_date))
  or ((v_ins and new.payment_terms is not null) or (not v_ins and new.payment_terms is distinct from old.payment_terms)) then
    if not (v_terms or v_send or v_billing) then
      raise exception 'You may not change an invoice''s terms or due date.' using errcode = 'insufficient_privilege';
    end if;
  end if;

  if (v_ins and coalesce(new.aging_excluded, false)) or (not v_ins and new.aging_excluded is distinct from old.aging_excluded) then
    if not (v_billing or (v_import and v_legacy)) then
      raise exception 'You may not exclude an invoice from ageing.' using errcode = 'insufficient_privilege';
    end if;
  end if;

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
      if not v_void then
        raise exception 'You may not clear an invoice''s state.' using errcode = 'insufficient_privilege';
      end if;
    end if;
  end if;

  if (v_ins and new.payment_status is not null) or (not v_ins and new.payment_status is distinct from old.payment_status) then
    raise exception 'Payment status is set by the payment provider, not from the app.'
      using errcode = 'insufficient_privilege';
  end if;

  return new;
end;
$$;

-- ═══ 5. the counters ask for the permission their use implies ═════════════
create or replace function public.guard_counter_caller(p_company_id text, p_keys text[])
returns void
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare k text;
begin
  if auth.uid() is null then return; end if;
  if p_company_id not in (select public.auth_company_ids()) then
    raise exception 'That company is not yours.' using errcode = 'insufficient_privilege';
  end if;
  foreach k in array p_keys loop
    if public.auth_has_permission(k, p_company_id) then return; end if;
  end loop;
  raise exception 'You may not allocate an invoice or credit-memo number.'
    using errcode = 'insufficient_privilege';
end;
$$;

revoke all on function public.guard_counter_caller(text, text[]) from public, anon;
grant execute on function public.guard_counter_caller(text, text[]) to authenticated, service_role;

create or replace function public.sync_invoice_next_seq(p_company_id text)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_next bigint;
begin
  perform public.guard_counter_caller(p_company_id, array['billing.configure', 'config.import_data']);

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

-- ═══ 6. an approved merchant can still save their own details ═════════════
create or replace function public.guard_kyc_status()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_current text;
begin
  if auth.uid() is null then return new; end if;

  -- Compare against the STORED row, not against OLD: the only writer is an
  -- upsert, and Postgres fires the BEFORE INSERT trigger before it resolves the
  -- conflict, so tg_op is INSERT and OLD is null on exactly the path this
  -- exemption exists for — an approved merchant editing their details.
  select status into v_current from public.company_kyc where company_id = new.company_id;

  if v_current is not null and new.status is not distinct from v_current then
    return new;
  end if;

  if new.status is distinct from 'not_started' and new.status is distinct from 'submitted' then
    raise exception 'Only STRATA can approve or decline a merchant application.'
      using errcode = 'insufficient_privilege';
  end if;

  return new;
end;
$$;

commit;
