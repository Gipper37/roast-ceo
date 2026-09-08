-- 🔴 Any tenant member could lock a colleague out of the floor in five calls.
--
-- `verify_team_pin(p_team_member_id, p_pin)` is SECURITY DEFINER and was granted
-- to `authenticated`. It takes ANY member id in the caller's company, and on a
-- wrong PIN it increments that member's `failed_count` and, at the threshold,
-- sets `locked_until`. Nothing checks that the caller is the person being
-- verified, or that the call came from a terminal.
--
-- Reproduced on staging 2026-09-08 as an ordinary member of the demo company:
-- five calls with wrong PINs against a colleague's id returned
-- invalid · invalid · invalid · invalid · locked, and the colleague's own
-- CORRECT PIN then returned {"ok": false, "reason": "locked"}.
--
-- That is a denial of service against the lock screen, which on a shared
-- terminal is a denial of service against the production floor — and once
-- verification of a food-safety record depends on a PIN, against the only way to
-- verify anything.
--
-- ── The fix ─────────────────────────────────────────────────────────────────
-- The grant was simply wrong. `verify_team_pin` has exactly one caller,
-- `terminal_pin_in`, which is itself SECURITY DEFINER and therefore keeps its
-- access as the function owner. Nothing in the frontend calls it directly (the
-- lock screen goes through `terminalPinIn`). So the call is taken away from
-- clients entirely rather than rate-limited: a lockout counter that only a
-- genuine unlock attempt can move needs no rate limit.
--
-- `anon` is revoked in the same breath. It could not reach a member — for anon,
-- auth_company_ids() is empty and the function returns 'invalid' before touching
-- a row — but it could still make the server compute a bcrypt hash on demand,
-- which is an unauthenticated CPU tap for no reason.
--
-- Found by an adversarial review of the log-framework design, which needs
-- two-person PIN verification and would have built straight on top of this.

begin;

revoke all on function public.verify_team_pin(text, text) from public, anon, authenticated;

comment on function public.verify_team_pin(text, text) is
  'INTERNAL. Callable only from terminal_pin_in (SECURITY DEFINER), never by a client: it moves the target member''s lockout counter, so exposing it lets any tenant member lock a colleague out of the terminal. See 20260908000003.';

-- Belt and braces: the same reasoning applies to the other PIN primitives that
-- move state for a member the caller names. set_team_pin authorises itself
-- (it raises 'You do not have permission to set a PIN for someone else'), and
-- terminal_set_own_pin resolves the actor from the open session rather than
-- taking a member id — both are safe to keep exposed. clear_team_pin is checked
-- here because it takes a member id from the caller.
do $$
declare v_has_check boolean;
begin
  select pg_get_functiondef(p.oid) ilike '%auth_has_permission%'
    into v_has_check
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'clear_team_pin'
   limit 1;
  if v_has_check is false then
    raise exception 'clear_team_pin takes a member id and does not authorise the caller — review before release.';
  end if;
end $$;

commit;
