-- A printed bin card made its roast undeletable.
--
-- MCR, on the Windows build, minutes after the release: charge a roast,
-- complete it, save it, then try to delete it. The delete was refused and
-- the operator saw the generic production error, which says nothing:
--
--   update or delete on table "roast_log" violates foreign key constraint
--   "bin_card_roast_log_id_fkey" on table "bin_card"
--
-- 20260908000024 gave bin_card an ON DELETE RESTRICT reference to roast_log.
-- RESTRICT is the right instinct for a traceability record and the wrong
-- answer for this one. A bin card is not an independent record: it is the
-- slip that rides along with one specific roast, minted from it and
-- describing only it. If that roast is being deleted then it did not happen,
-- or it was entered by mistake, and a card for a roast that does not exist
-- documents nothing. Every other dependent of roast_log that is part of the
-- roast rather than downstream of it already cascades: roast_log_recipes,
-- roast_log_lot_consumption, roast_lot_shortfall.
--
-- pack_run_source is deliberately NOT changed here. That one records that
-- bagged coffee came from a given roast, and cascading it would quietly cut
-- the chain between a bag on a shelf and the batch it came out of. A roast
-- that has been bagged SHOULD refuse to be deleted. What it must not do is
-- refuse in a way nobody can read, and that is a message to fix in the app,
-- not a constraint to loosen.

begin;

alter table public.bin_card
  drop constraint if exists bin_card_roast_log_id_fkey;

alter table public.bin_card
  add constraint bin_card_roast_log_id_fkey
  foreign key (roast_log_id) references public.roast_log(roast_log_id)
  on delete cascade;

do $probe$
declare v_action char;
begin
  select confdeltype into v_action
    from pg_constraint where conname = 'bin_card_roast_log_id_fkey';
  -- 'c' = cascade. 'r' would mean the drop/add did not take.
  if v_action is distinct from 'c' then
    raise exception 'bin_card still does not cascade: confdeltype is %', coalesce(v_action::text, 'missing');
  end if;

  -- And the one we are deliberately leaving alone is still holding.
  if (select confdeltype from pg_constraint where conname = 'pack_run_source_roast_log_id_fkey') <> 'r' then
    raise exception 'pack_run_source should still RESTRICT: a bagged roast must not be silently deletable';
  end if;
end
$probe$;

commit;
