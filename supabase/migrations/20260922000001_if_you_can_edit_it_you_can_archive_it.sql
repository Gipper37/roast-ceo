-- A roastmaster could edit a recipe and not archive it.
--
-- The owner, on being shown the Archive button hidden instead: "he can
-- archive recipes you fucking idiot." The button was right; the permission
-- was wrong. Hiding it was fixing the symptom in the wrong direction.
--
-- The pattern is wider than recipes. Every one of these roles already holds
-- the matching .edit key, which is the stronger capability: editing a recipe
-- changes what every future batch of it will be, while archiving only takes
-- it out of the pickers and is reversible from the same screen. Granting edit
-- and withholding archive is not a smaller permission, it is an inconsistent
-- one, and it shows up as a button that refuses.
--
--   roastmaster        recipe.archive     had edit, not archive
--   roastmaster        product.archive    had edit, not archive
--   roastmaster        customer.archive   had edit, no row at all
--   roastmaster        supplier.archive   had edit, no row at all
--   roastmaster        contact.archive    had edit, not archive
--   assistant_roaster  customer.archive   had edit, no row at all
--
-- Nothing here is destructive: archive is a flag, the row keeps its history,
-- and every one of these surfaces offers Restore in the same place.

begin;

insert into public.role_permissions (role_id, permission_id, granted)
values
  ('roastmaster',       'recipe.archive',   true),
  ('roastmaster',       'product.archive',  true),
  ('roastmaster',       'customer.archive', true),
  ('roastmaster',       'supplier.archive', true),
  ('roastmaster',       'contact.archive',  true),
  ('assistant_roaster', 'customer.archive', true)
on conflict (role_id, permission_id) do update set granted = true;

do $probe$
declare v_missing text;
begin
  -- Every role that can edit one of these must now be able to archive it.
  select string_agg(e.role_id || '.' || replace(e.permission_id,'.edit','.archive'), ', ')
    into v_missing
  from public.role_permissions e
  left join public.role_permissions a
    on a.role_id = e.role_id
   and a.permission_id = replace(e.permission_id, '.edit', '.archive')
  where e.permission_id in ('recipe.edit','product.edit','customer.edit','supplier.edit','contact.edit')
    and e.granted is true
    and coalesce(a.granted, false) is false;

  if v_missing is not null then
    raise exception 'still able to edit but not archive: %', v_missing;
  end if;
end
$probe$;

commit;
