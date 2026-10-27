-- Printing an invoice is not emailing one.
--
-- Owner, 2026-10-27: *"wsorders (roastery manager and their staff) need to be
-- able to print invoices. so that means the invoice number gets minted at that
-- point and thats fine. but that just changes the shape of our invoicing
-- permissions. maybe we say that a staff can't email an invoice but they can
-- print one? roastery manager could email one."*
--
-- 🔴 THE SEAM IS ALREADY IN THE DESCRIPTION OF THE KEY WE HAVE. invoice.send
-- reads: "Finalize an order into a STRATA invoice (allocate number, lock, mark
-- open) AND email the PDF." Two acts, one key. Finalizing is what a packer at
-- the bench needs in order to hand a customer a numbered document; emailing is
-- a different thing, sent in the roastery's name to an address on file, and it
-- is the one worth withholding from someone who is there to pack boxes.
--
-- So the key splits along the seam that was already written into it:
--
--     invoice.print   finalize (allocate the number) and put it on paper
--     invoice.send    all of that, and email it to the customer
--
-- WHY PRINTING STILL MINTS A NUMBER. Because he is right that it must: a
-- document with no number is not an invoice, and two prints of the same order
-- have to be the same invoice. That is why this is a permission and not a free
-- action -- it is an accounting event, just one a packer may legitimately
-- cause.
--
-- WHO GETS IT. The bench roles plus everyone who could already send:
-- staff, roastery_manager, roastmaster, assistant_roaster, and the four that
-- hold invoice.send today. NOT accounting_view (read-only by definition),
-- equipment_tech, or sales_person -- none of them is standing at the packing
-- bench, and each is one toggle away in /app/dev/permissions if that turns out
-- to be wrong.
--
-- 🔴 AND THE TERMINAL INTERSECTION IS WHY THE LIST IS THAT WIDE. A terminal
-- login's authority is capped by whoever is PIN'd in: auth_has_permission
-- requires BOTH the terminal's role and the pinned person's role to grant the
-- key. wsorders is a roastery_manager, so granting only roastery_manager would
-- still deny every roastmaster who PINs in at it. Both sides of the
-- intersection need the key or neither side gets it.
--
-- roastery_manager also gains invoice.send, which is the other half of what he
-- asked: the manager can email, the staff cannot.
--
-- PLAN GATE unchanged from invoice.send: enterprise and enterprise_plus. It
-- mints an invoice number, so it is the same accounting capability and belongs
-- behind the same plan. Both MCR and Social Hour are enterprise_plus/active,
-- so the gate is already satisfied for them and the role was the only block.
--
-- 🔴 THIS MIGRATION APPLIES BEFORE ANY FRONTEND NAMES THE KEY. An unknown
-- permission key resolves to DENIED, silently, so a UI shipped first would
-- simply stop working with nothing to say why.

begin;

insert into public.permissions
  (permission_id, category, label, description, default_deny_message, is_plan_gated, sort_order)
values (
  'invoice.print',
  'Payments',
  'Print invoices',
  'Finalize an order into a STRATA invoice (allocate number, lock, mark open) and print it. Does NOT email the customer -- that is invoice.send. Enterprise plans, invoice-of-record mode only.',
  'You do not have permission to issue invoices.',
  true,
  51
)
on conflict (permission_id) do update
  set category             = excluded.category,
      label                = excluded.label,
      description          = excluded.description,
      default_deny_message = excluded.default_deny_message,
      is_plan_gated        = excluded.is_plan_gated,
      sort_order           = excluded.sort_order;

-- The roles that can issue and print.
insert into public.role_permissions (role_id, permission_id, granted)
select r, 'invoice.print', true
  from unnest(array[
    'staff','roastery_manager','roastmaster','assistant_roaster',
    'accounting_admin','company_admin','facility_admin','manager'
  ]) as r
on conflict (role_id, permission_id) do update set granted = excluded.granted;

-- The manager can email; the staff cannot. This is the half that changes an
-- EXISTING key, so it is stated on its own rather than folded into the list.
insert into public.role_permissions (role_id, permission_id, granted)
values ('roastery_manager', 'invoice.send', true)
on conflict (role_id, permission_id) do update set granted = excluded.granted;

-- Same plan gate as invoice.send: copied from it rather than retyped, so the
-- two cannot drift if the plans are ever re-cut.
insert into public.plan_permissions (plan_id, permission_id, granted)
select pp.plan_id, 'invoice.print', pp.granted
  from public.plan_permissions pp
 where pp.permission_id = 'invoice.send'
on conflict (plan_id, permission_id) do update set granted = excluded.granted;

do $$
declare
  v_n int;
  r   record;
begin
  if not exists (select 1 from public.permissions where permission_id = 'invoice.print') then
    raise exception 'invoice.print was not registered';
  end if;

  -- Every role that can email must also be able to print, or a manager who
  -- presses Print gets denied for a capability they already exceed.
  for r in
    select rp.role_id from public.role_permissions rp
     where rp.permission_id = 'invoice.send' and rp.granted
  loop
    if not exists (
      select 1 from public.role_permissions p
       where p.role_id = r.role_id and p.permission_id = 'invoice.print' and p.granted
    ) then
      raise exception 'role % can send invoices but cannot print them', r.role_id;
    end if;
  end loop;

  -- The owner's rule, asserted both ways rather than assumed.
  if exists (select 1 from public.role_permissions
              where role_id='staff' and permission_id='invoice.send' and granted) then
    raise exception 'staff can email invoices; the owner asked that they cannot';
  end if;
  if not exists (select 1 from public.role_permissions
                  where role_id='staff' and permission_id='invoice.print' and granted) then
    raise exception 'staff cannot print invoices; the owner asked that they can';
  end if;
  if not exists (select 1 from public.role_permissions
                  where role_id='roastery_manager' and permission_id='invoice.send' and granted) then
    raise exception 'roastery_manager cannot email invoices; the owner asked that they can';
  end if;

  -- The plan gate has to match, or printing is available on a plan that cannot
  -- invoice at all.
  select count(*) into v_n
    from public.plan_permissions a
    join public.plan_permissions b
      on b.plan_id = a.plan_id and b.permission_id = 'invoice.send'
   where a.permission_id = 'invoice.print' and a.granted is distinct from b.granted;
  if v_n <> 0 then
    raise exception 'invoice.print and invoice.send disagree on % plan(s)', v_n;
  end if;

  raise notice 'invoice.print registered; staff print, roastery_manager prints and emails';
end $$;

commit;
