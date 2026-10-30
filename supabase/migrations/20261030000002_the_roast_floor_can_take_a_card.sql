-- The roast floor can take a card.
--
-- MCR's only shared terminal login ("Wholesale Orders") is a `roastery_manager`,
-- and that role did not hold `payment.charge_card`. So the one machine standing
-- where a customer actually hands over a card could not charge it, and no PIN
-- fixed that: a terminal session is an INTERSECTION of the login's role and the
-- PIN'd-in person's, so a manager PIN-in could not lend the terminal a grant the
-- terminal's own role lacks. Owner's decision: grant it, "but only roastmaster
-- and up".
--
-- "AND UP" IS THE DECLARED LADDER, NOT A GUESS. ROLE_HIERARCHY in
-- lib/permissions/constants.ts, mirrored by public.role_rank(), ranks
-- company_admin 0, facility_admin 1, manager 2, roastery_manager 3,
-- roastmaster 4. The first three already held the key; this adds the two that
-- did not. Everything below roastmaster -- equipment_tech, assistant_roaster,
-- sales_person, staff -- is untouched and still cannot charge a card.
--
-- 🔴 accounting_admin KEEPS IT, and is deliberately not revoked. It ranks 9,
-- so a literal reading of "roastmaster and up" would strip it. But the
-- hierarchy's own comment says the accounting track is "placed low so only
-- admins manage them" and that "broad object access is granted via
-- permissions, not hierarchy" -- rank 9 is team-management authority, not
-- capability. Whoever does the books is precisely who takes a payment, and
-- they have held this key all along.
--
-- 🔴 THIS DOES NOT ARM AN UNATTENDED TERMINAL. lib/permissions/server.ts:291:
-- "A terminal with nobody PIN'd in can do NOTHING." The terminal cap is
-- narrow-only -- it can remove a grant, never add one -- so the lock screen
-- still denies every key, and after this migration a card can be charged at
-- that terminal only while a roastmaster-or-above is PIN'd in at that device.
--
-- The plan gate is unchanged and still applies on top: `payment.charge_card`
-- is granted on enterprise and enterprise_plus only, and denied on pro and
-- starter. A role grant alone does not open it for a company on a lower plan.

begin;

insert into public.role_permissions (role_id, permission_id, granted, updated_by)
values
  ('roastery_manager', 'payment.charge_card', true, 'migration:20261030000002'),
  ('roastmaster',      'payment.charge_card', true, 'migration:20261030000002')
on conflict (role_id, permission_id) do update
  set granted    = true,
      deny_message = null,
      updated_at = now(),
      updated_by = 'migration:20261030000002';

do $$
declare
  missing text;
begin
  -- Post-condition. Every role at rank <= 4 must now hold the key. This can
  -- fail: if the insert were skipped, the terminal would still refuse to
  -- charge and the symptom would read as a PIN fault rather than a missing
  -- grant -- which is exactly how this bug presented in the first place.
  select string_agg(r, ', ' order by r) into missing
    from unnest(array[
      'company_admin', 'facility_admin', 'manager',
      'roastery_manager', 'roastmaster'
    ]) as r
   where not exists (
     select 1 from public.role_permissions rp
      where rp.role_id = r
        and rp.permission_id = 'payment.charge_card'
        and rp.granted
   );

  if missing is not null then
    raise exception 'payment.charge_card is not granted to: %', missing;
  end if;

  raise notice 'payment.charge_card now held by roastmaster and up (5 roles); accounting_admin retained';
end $$;

commit;
