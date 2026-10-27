-- Probe: does PostgREST hand request headers to SQL on this project?
--
-- Per-device terminals need the DATABASE to know which physical machine is
-- asking, because auth_has_permission is called from RLS policies and policies
-- take no arguments. The app layer already knows (a cookie), but narrowing
-- only in the app and leaving the database clause broad would make every
-- device at a terminal account hold the UNION of everyone currently PIN'd in.
-- That is worse than today, so it is not an option.
--
-- The mechanism is PostgREST's `request.headers` GUC. Nothing in this project
-- uses it yet, so there is no existing proof it is populated here, and I am not
-- building an authentication change on an assumption.
--
-- This function exists only to answer that question from a real REST call. It
-- returns a header value and nothing else: no table is read, no identity is
-- consulted, and it is granted to anon deliberately so the probe needs no
-- session. It is dropped by the migration that uses the answer.

begin;

create or replace function public.probe_request_header(p_name text)
returns text
language sql
stable
as $function$
  select coalesce(
    nullif(current_setting('request.headers', true), '')::json ->> p_name,
    '(header-not-present)'
  );
$function$;

comment on function public.probe_request_header(text) is
  'TEMPORARY. Answers whether PostgREST populates request.headers on this project, for the per-device terminal work. Drop once answered.';

grant execute on function public.probe_request_header(text) to anon, authenticated, service_role;

do $$
begin
  -- From psql there is no request, so the GUC is unset and this returns the
  -- sentinel. That is the EXPECTED result here and proves only that the
  -- function runs; the real answer comes from a REST call.
  if public.probe_request_header('x-terminal-device') is null then
    raise exception 'probe_request_header returned null rather than the sentinel';
  end if;
  raise notice 'probe installed; from psql it reads %', public.probe_request_header('x-terminal-device');
end $$;

commit;
