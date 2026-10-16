-- collection_is_reserved is SECURITY DEFINER, so take it away from the browser.
--
-- 20261015000006 said the right thing and did the wrong one:
--
--     -- SECURITY DEFINER over another tenant's rows, so not for the browser.
--     revoke all on function public.collection_is_reserved(text) from public;
--
-- 🔴 `revoke ... from public` DOES NOT REVOKE FROM `authenticated`. That is a
-- gotcha already written down in this project
-- (gotcha_revoke_from_public_does_not_revoke_from_authenticated), and the
-- comment above the revoke proves the intent was exactly what the statement
-- failed to achieve. Measured on prod after the 2026-10-15 release:
--     has_function_privilege('authenticated', 'collection_is_reserved(text)', 'EXECUTE') = true
--
-- Why it matters: the function is SECURITY DEFINER, so it reads
-- public.collection with RLS bypassed. A logged-in user of one company could
-- call it over PostgREST with ANOTHER company's collection id and learn
-- whether that collection is reserved -- one boolean per id they can guess.
--
-- Impact TODAY is nil and that is luck, not design: 0 of prod's 11 collections
-- carry any of the three allowlists, so it returns false for every id. It
-- becomes a real cross-tenant leak the first time a roaster reserves a
-- collection, which is the feature the same release shipped.
--
-- 🔴 A NEW FILE, not an edit to 006 or 017. Both are already applied to prod
-- and to staging, and `supabase db push` never re-applies an edited file --
-- which is what cost four CI rounds on 2026-10-15. See
-- gotcha_never_edit_an_applied_migration.
--
-- Its three callers are unaffected: merge_product_groups and the two
-- product_group_collection write policies all execute as the owner, not as
-- the caller, so they never needed the caller to hold EXECUTE.

begin;

revoke execute on function public.collection_is_reserved(text) from public;
revoke execute on function public.collection_is_reserved(text) from anon;
revoke execute on function public.collection_is_reserved(text) from authenticated;

do $verify$
declare
  v_who text;
begin
  -- Nobody the browser can be may execute it. Checked per role rather than
  -- trusting the revoke, because that is the whole lesson of this file.
  select string_agg(g, ', ') into v_who
    from unnest(array['public', 'anon', 'authenticated']) g
   where has_function_privilege(g, 'public.collection_is_reserved(text)', 'EXECUTE');
  if v_who is not null then
    raise exception 'collection_is_reserved is still executable by: %', v_who;
  end if;

  -- And it still WORKS for its real callers, which run as the owner. If this
  -- raised, the revoke had gone too far.
  if public.collection_is_reserved('definitely-not-a-collection-id') then
    raise exception 'collection_is_reserved answered true for a nonexistent collection';
  end if;

  raise notice 'collection_is_reserved is owner-only; its three callers run as the owner';
end $verify$;

commit;
