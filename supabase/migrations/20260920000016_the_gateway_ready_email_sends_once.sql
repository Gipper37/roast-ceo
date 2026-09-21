-- provider_credentials records HOW the keys arrived, which is the whole of who to call when they stop working.
--
-- ORDER: 3 of 4. Nothing. Must FOLLOW 20260920000010, which creates the table. Until it lands, connectionSource reads null everywhere, which is "we do not know" and keeps the old wording; nothing guesses in either direction.

begin;

-- The roaster-facing copy differs by source and there is no other way to
-- tell. created_by holds a team user_id for a roaster's own paste and an
-- operator's email for a STRATA connect, which is a tell and not an answer.
--
-- A roaster who pasted their own keys can be asked to replace them. A
-- roaster whose Activity Pay account STRATA connected has never seen that
-- key, has no login that would show it, and AP display a key exactly once,
-- so "replace the pair from your Activity Pay account" is a dead end wearing
-- the tone of an instruction.
--
-- The default is 'roaster' and SaveApCredentialsInput.connectionSource is
-- REQUIRED in TypeScript precisely so nothing relies on it. Defaulting is
-- what made this wrong the first time: every pair a STRATA operator minted
-- would have read as roaster-pasted, and both surfaces would have acted on
-- it, pointing the two halves of the fix at two different wrong people.
alter table public.provider_credentials
  add column if not exists connection_source text not null default 'roaster';

alter table public.provider_credentials
  drop constraint if exists provider_credentials_connection_source_chk;
alter table public.provider_credentials
  add constraint provider_credentials_connection_source_chk
    check (connection_source in ('roaster','strata_operator','provider_api'));

comment on column public.provider_credentials.connection_source is
  'How these keys got here: the roaster pasted them, a STRATA operator entered them on the roaster''s behalf, or Activity Pay provisioned them. ''provider_api'' is unused today and is the slot an Activity Pay provisioning API lands in, so that day costs no schema change.';

commit;
