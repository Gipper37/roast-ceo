-- Drop the two MCR order backup tables.
--
-- They were taken on 2026-08-05 by scripts/mcr_orders_snapshot_and_scrap.sql as
-- the restore point for re-running MCR's QuickBooks import onto clean ground.
-- That operation was never executed, and the snapshot has been overtaken:
--
--   3,801 orders / 13,331 lines captured on 2026-08-05
--   3,799 of those orders are still LIVE and untouched — the scrap never ran
--   the other 2 were deliberately deleted in the 2026-08-28 quote cleanup
--   0 live imported orders are missing from the backup — nothing has been
--     imported since, so the snapshot is not protecting anything newer either
--
-- The owner, 2026-09-16: *"yes you can drop the backup tables if they are not
-- going to be used in the long term backup solution we build"*. They are not —
-- they are a one-off `create table as` of one tenant's orders from six weeks
-- ago, in a format nothing reads. Whatever gets built will produce its own
-- exports.
--
-- Before dropping, the two rows that existed ONLY here were captured at full
-- fidelity to scripts/mcr_backup_residue_2026-09-16.json — all 78 columns of
-- both orders and all 11 of their lines. The existing
-- mcr_deleted_quotes_snapshot_2026-08-28.tsv records the same two orders but
-- only as a 9-column summary, so it was not sufficient on its own. Nothing is
-- lost by this migration.
--
-- The trap that made this worth doing rather than just tidy: the script created
-- its snapshot with `create table if not exists`, so running it again would
-- reuse this stale table and then delete live orders — while its own guard read
-- the same stale table, saw exactly 3,801 / 13,331, and reported success. That
-- script is fixed in the same commit; these tables are the ammunition it was
-- pointing at its own foot.

begin;

do $$
declare v_orders int; v_details int;
begin
  if to_regclass('public.mcr_orders_backup_20260805') is null then
    raise notice 'mcr_orders_backup_20260805 already gone — nothing to drop';
    return;
  end if;
  select count(*) into v_orders  from public.mcr_orders_backup_20260805;
  select count(*) into v_details from public.mcr_order_details_backup_20260805;
  raise notice 'dropping MCR snapshot: % orders, % details', v_orders, v_details;

  -- Refuse if the snapshot turns out to hold rows that are NOT live and NOT in
  -- the committed residue file. The count is the one asserted in that file; if
  -- it has moved, something happened since 2026-09-16 and this is no longer a
  -- drop of superseded data.
  if (select count(*) from public.mcr_orders_backup_20260805 b
       where not exists (select 1 from public.orders o where o.order_id = b.order_id)) <> 2 then
    raise exception 'the snapshot holds rows that are neither live nor in scripts/mcr_backup_residue_2026-09-16.json — capture them before dropping';
  end if;
end
$$;

drop table if exists public.mcr_order_details_backup_20260805;
drop table if exists public.mcr_orders_backup_20260805;

do $probe$
begin
  if to_regclass('public.mcr_orders_backup_20260805') is not null
     or to_regclass('public.mcr_order_details_backup_20260805') is not null then
    raise exception 'the MCR snapshot tables are still present';
  end if;
end
$probe$;

commit;
