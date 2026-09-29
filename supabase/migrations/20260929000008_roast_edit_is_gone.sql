-- Remove roast.edit. It is a legacy alias that nothing has read for a long time.
--
-- `roast.edit` and `roast.edit_completed` carried near-identical labels ("Edit
-- completed roasts" and "Edit completed (post-drop) roasts"), the same five
-- roles, and the same four plans. One of them is live and one is scenery.
--
-- PROVED DEAD before deleting, on prod:
--   RLS policies naming it ........ 0
--   pg_proc bodies naming it ...... 0
--   frontend call sites ........... 0
-- The single reference anywhere is its own declaration in
-- /Users/wanderingaloha/stratos/lib/permissions/constants.ts:153, which labels
-- it "legacy alias -- keep for now until Phase B sweeps callsites". The sweep is
-- this. The live key is roast.edit_completed, named by five call sites.
--
-- Why it is worth deleting rather than leaving: two keys over one action is the
-- failure this project has now written three migrations to undo
-- (20260926000014, 20260929000003, and the temptation resisted in
-- 20260929000007). A dead key in the role matrix tells an admin they have
-- granted something, and they have granted nothing. It also makes the next
-- person choosing a key pick a coin flip.

begin;

delete from public.role_permissions where permission_id = 'roast.edit';
delete from public.plan_permissions  where permission_id = 'roast.edit';
delete from public.permissions       where permission_id = 'roast.edit';

do $verify$
declare v_bad int;
begin
  if exists (select 1 from public.permissions where permission_id = 'roast.edit') then
    raise exception 'roast.edit is still registered';
  end if;
  select count(*) into v_bad from public.role_permissions where permission_id = 'roast.edit';
  if v_bad > 0 then raise exception '% orphan role grant(s) left behind', v_bad; end if;
  select count(*) into v_bad from public.plan_permissions where permission_id = 'roast.edit';
  if v_bad > 0 then raise exception '% orphan plan row(s) left behind', v_bad; end if;

  -- The key that DOES the job is untouched, and still reaches every role that
  -- can write a roast -- including the assistant_roaster grant one migration ago.
  if not exists (select 1 from public.permissions where permission_id = 'roast.edit_completed') then
    raise exception 'roast.edit_completed is missing; this deleted the wrong key';
  end if;
  select count(*) into v_bad
    from public.role_permissions rl
   where rl.permission_id = 'roast.log' and rl.granted
     and not exists (select 1 from public.role_permissions re
                      where re.role_id = rl.role_id
                        and re.permission_id = 'roast.edit_completed' and re.granted);
  if v_bad > 0 then
    raise exception '% role(s) can write roast_log but cannot pass the Edit Roast gate', v_bad;
  end if;
end;
$verify$;

commit;
