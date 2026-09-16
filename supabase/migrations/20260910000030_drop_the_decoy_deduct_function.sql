-- Drop deduct_from_lot_on_roast. It is a decoy.
--
-- It looks exactly like the function that deducts green when a roast is
-- charged, it carries a "skip historical inserts" clock guard, and it is
-- referenced by four historical migrations. It is attached to NO table
-- (pg_trigger) and called by NOTHING (pg_proc.prosrc) — verified on staging
-- 2026-09-15.
--
-- The live path is:
--   roast_log AFTER INSERT → trg_lot_consumption_recompute
--     → roast_log_lot_recompute → deduct_one_roast
--
-- This cost real time: asked to make a back-dated roast deduct, I read this
-- function, "fixed" its guard, and the test showed nothing changed. Worse, it
-- anchored a wrong belief — I told the owner back-dated roasts do not deduct,
-- when in fact they always have.
--
-- Removing it rather than leaving a comment, per the standing rule: when
-- superseding logic, REMOVE the dead path once nothing reads it. The four
-- migrations that mention it are history and stay as they are; migrations are
-- never edited.

begin;

do $guard$
begin
  -- Refuse to drop it if anything picked it up since.
  if exists (
    select 1 from pg_trigger t
      join pg_proc p on p.oid = t.tgfoid
     where p.proname = 'deduct_from_lot_on_roast' and not t.tgisinternal
  ) then
    raise exception 'deduct_from_lot_on_roast is attached to a trigger after all — not dropping it';
  end if;

  if exists (
    select 1 from pg_proc
     where pronamespace = 'public'::regnamespace
       and proname <> 'deduct_from_lot_on_roast'
       and prosrc ilike '%deduct_from_lot_on_roast%'
  ) then
    raise exception 'something calls deduct_from_lot_on_roast — not dropping it';
  end if;
end
$guard$;

drop function if exists public.deduct_from_lot_on_roast();

do $probe$
begin
  if exists (select 1 from pg_proc
              where pronamespace = 'public'::regnamespace
                and proname = 'deduct_from_lot_on_roast') then
    raise exception 'deduct_from_lot_on_roast survived the drop';
  end if;
  -- And the real one is still there.
  if not exists (select 1 from pg_proc
                  where pronamespace = 'public'::regnamespace
                    and proname = 'deduct_one_roast') then
    raise exception 'deduct_one_roast is missing — the live deduct path is gone';
  end if;
end
$probe$;

commit;
