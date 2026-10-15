-- `session_expires_at` has to be enforced by the FENCE, not by a sweep.
--
-- 20261015000007 gave a support session a real `team` row with an expiry, and
-- a CHECK makes a dev_session without one impossible to write. What it did NOT
-- do is make the expiry mean anything to row level security:
--
--   auth_company_ids() := select company_id from team
--                          where auth_user_id = auth.uid() and is_active
--
-- so an expired row kept granting access until something deleted it. The
-- sweeps run when a developer starts or ends a session, which is exactly the
-- moment a developer is present -- and the case that needs the guarantee is
-- the one where they are NOT: a closed laptop, a crashed tab, a browser
-- profile that lost the cookie. Observed on dev 2026-10-15: a membership
-- outlived its session because the cookie was gone and nothing ran.
--
-- An expiry a cleanup job has to honour is a promise. An expiry in the
-- predicate is a fact. This makes the row stop granting the moment it expires,
-- whether or not anybody sweeps it, and leaves the sweep as tidying rather
-- than as the security control.
--
-- ── This NARROWS, and narrows only ────────────────────────────────────────
--
-- `session_expires_at` is NULL on every ordinary membership and the CHECK from
-- 20261015000007 keeps it that way, so the added clause is true for every row
-- that is not a support session. No account, floor staff row or terminal is
-- affected. Proven below rather than asserted: the company list for every
-- existing team row is identical either side of the change.

begin;

-- Snapshot what the CURRENT definition grants, per team row, so the verify
-- block can compare rather than trust. Taken before the replace.
create temporary table _grants_before_20261015000008 on commit drop as
  select auth_user_id, company_id
    from public.team
   where auth_user_id is not null
     and coalesce(is_active, true) = true
     and company_id is not null;

create or replace function public.auth_company_ids()
 returns setof text
 language sql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
  SELECT company_id
  FROM public.team
  WHERE auth_user_id = auth.uid()
    AND COALESCE(is_active, true) = true
    AND company_id IS NOT NULL
    -- A support session stops granting the moment it expires. NULL is every
    -- ordinary membership, which never expires.
    AND (session_expires_at IS NULL OR session_expires_at > now());
$function$;

do $verify$
declare v_bad int; v_def text;
begin
  -- 1. The clause is actually in the body. Cheap, and it catches a replace
  --    that silently landed the old text.
  select pg_get_functiondef(oid) into v_def from pg_proc where proname = 'auth_company_ids';
  if v_def is null or v_def not like '%session_expires_at%' then
    raise exception 'auth_company_ids() does not consult session_expires_at';
  end if;

  -- 2. 🔴 It still SECURITY DEFINER and still STABLE. A replace that dropped
  --    either would change who the function runs as, which is the whole fence.
  if not exists (
    select 1 from pg_proc where proname = 'auth_company_ids'
      and prosecdef = true and provolatile = 's'
  ) then
    raise exception 'auth_company_ids() lost SECURITY DEFINER or STABLE';
  end if;

  -- 3. 🔴 NOBODY LOST ACCESS. Every (user, company) pair the old definition
  --    would have returned is still returned, because no existing row has an
  --    expiry. Compared as a set difference rather than as a count.
  select count(*) into v_bad
    from (
      select auth_user_id, company_id from _grants_before_20261015000008
      except
      select auth_user_id, company_id
        from public.team
       where auth_user_id is not null
         and coalesce(is_active, true) = true
         and company_id is not null
         and (session_expires_at is null or session_expires_at > now())
    ) q;
  if v_bad > 0 then
    raise exception '% (user, company) grant(s) disappeared; this migration must take none away', v_bad;
  end if;

  raise notice 'an expired support session now grants nothing; % grant(s) unchanged',
    (select count(*) from _grants_before_20261015000008);
end $verify$;

commit;
