-- authenticated gets EXECUTE on collection_is_reserved back, because an RLS
-- policy runs as the CALLER.
--
-- 🔴 I BROKE THIS THIS MORNING. `20261016000001` revoked EXECUTE on
-- `public.collection_is_reserved(text)` from `public, anon, authenticated`,
-- and its verify block asserted that was safe because *"its three callers run
-- as the owner"*. That premise was wrong. The three callers are POLICIES:
--
--     product_group_collection_insert   (WITH CHECK)
--     product_group_collection_update   (USING + WITH CHECK)
--     product_group_collection_delete   (USING)
--
-- A policy predicate is evaluated as the INVOKING role, not as the table
-- owner. So from the moment that migration reached prod, every attempt by a
-- logged-in user to add, move or remove a product's collection membership
-- failed with `permission denied for function collection_is_reserved`.
--
-- Owner, on the Sauces collection, 2026-10-16: *"permission denied."*
--
-- ── WHY GRANTING IT BACK IS SAFE, AND WHAT STAYS REVOKED ──────────────────
--
-- `anon` and `public` stay revoked. That was the actual hole and it is still
-- closed: a signed-out visitor has no business asking whether a collection is
-- reserved.
--
-- `authenticated` learns NOTHING it could not already read. The function takes
-- a collection id and returns a boolean derived from `exclusive_to_customer_ids`,
-- `exclusive_to_chain_ids` and `excluded_from_customer_ids` on `collection` --
-- a row that same tenant member can SELECT directly under
-- `tenant_company_access`. It is SECURITY DEFINER and STABLE, it takes an id
-- and returns a boolean, and it reveals nothing across tenants: a collection
-- belonging to another company reads as not-reserved either way, which is what
-- a stranger's row should look like.
--
-- ── THE RULE THIS COST US ─────────────────────────────────────────────────
--
-- A REVOKE IS ONLY PROVEN BY CALLING THE THING AS THE ROLE YOU REVOKED FROM.
-- The old verify block checked that the grant was gone and asserted a premise
-- about who calls it. Both passed. The staging rehearsal could not catch it
-- either, because it applies SQL as `postgres` and never exercises a policy.
-- So this file's verify block SETS ROLE and makes the call.
--
-- Before revoking EXECUTE on anything again: grep
-- `pg_policies.qual || with_check` for the function name. If a policy names
-- it, the roles that policy applies to MUST keep EXECUTE.

begin;

grant execute on function public.collection_is_reserved(text) to authenticated;

-- Said again rather than assumed: the ones that should not have it, still do not.
revoke execute on function public.collection_is_reserved(text) from public, anon;

do $verify$
declare
  v_collection text;
  v_result     boolean;
begin
  -- 1. The grants are what we think they are.
  if not has_function_privilege('authenticated', 'public.collection_is_reserved(text)', 'EXECUTE') then
    raise exception 'authenticated still cannot execute collection_is_reserved; the three write policies on product_group_collection will keep failing';
  end if;
  if has_function_privilege('anon', 'public.collection_is_reserved(text)', 'EXECUTE') then
    raise exception 'anon can execute collection_is_reserved; that was the hole 20261016000001 closed';
  end if;

  -- 2. 🔴 CALLED AS THE ROLE. This is the check whose absence shipped the bug:
  --    a privilege test that reads the catalogue can agree with itself while
  --    the actual call raises 42501.
  --    🔴 AND IT GIVES THE ROLE BACK BY ABORTING, NOT BY `RESET ROLE`.
  --    The first version of this file used `reset role` and CI's
  --    db-push-staging failed on the line AFTER the migration succeeded:
  --        ERROR: permission denied for schema supabase_migrations
  --        INSERT INTO supabase_migrations.schema_migrations(...)
  --    `RESET ROLE` does not mean "go back to postgres". It reverts to the
  --    SESSION role, and the Supabase CLI connects on a limited login role
  --    ("Initialising login role...") and raises itself with SET ROLE. So the
  --    reset stripped the CLI's own privileges and it could no longer record
  --    the version it had just applied.
  --
  --    A SET LOCAL inside a subtransaction is undone when that subtransaction
  --    ABORTS, so this block always ends by raising a sentinel and swallowing
  --    it. The role is restored by the abort, whatever happened inside, and
  --    nothing in the surrounding session is touched.
  begin
    select id into v_collection from public.collection limit 1;
    execute 'set local role authenticated';
    if v_collection is not null then
      execute 'select public.collection_is_reserved($1)' into v_result using v_collection;
    end if;
    raise exception 'ZZROLE_OK';
  exception
    when insufficient_privilege then
      raise exception 'calling collection_is_reserved as authenticated raised insufficient_privilege; the grant did not take';
    when others then
      if sqlerrm <> 'ZZROLE_OK' then raise; end if;
  end;

  -- The abort above must have given the role back. Said out loud, because the
  -- failure mode it guards is silent until something else needs a privilege.
  if current_user <> session_user and current_setting('role', true) = 'authenticated' then
    raise exception 'the probe left the session as authenticated';
  end if;

  -- 3. And the policies that need it are still the ones we think they are, so
  --    a future revoke has something to find.
  if (select count(*) from pg_policies
       where schemaname = 'public'
         and coalesce(qual, '') || coalesce(with_check, '') like '%collection_is_reserved%') < 3 then
    raise exception 'fewer than three policies name collection_is_reserved; this grant may no longer be needed, or a policy was lost';
  end if;

  raise notice 'authenticated can call collection_is_reserved again; anon still cannot';
end $verify$;

commit;
