-- Create public.provider_credentials: one row per (company_id, provider) holding the tenant's Activity Pay identity. RLS on, read-only for tenant members, both encrypted columns unreachable over PostgREST. This differs from the builder's proposal by adding verification_error, which app/app/(dev)/actions.ts selects and recordApCredentialCheckFailure() writes.
--
-- ORDER: 1 of 3. Nothing hard-blocks on it any more: resolveApCredentials now reads a missing relation as 'no row' and falls through to the deployment keys, so the frontend may ship first without turning cards off. Apply it before anyone is sent to the keys screen, because there is nowhere to store what they paste until it exists.

begin;

-- One Activity Pay merchant account per roaster: the gateway identity is a
-- property of the TENANT, not of the deployment. Two global environment
-- variables meant STRATA could serve exactly one roaster's payments, and
-- onboarding a second was not hard but impossible.
create table if not exists public.provider_credentials (
  company_id                text        not null references public.companies(company_id) on delete cascade,
  provider                  text        not null default 'activitypay',
  environment               text        not null,
  public_key                text        not null,
  secret_key_encrypted      text        not null,
  secret_key_last4          text,
  merchant_id               text,
  merchant_name             text,
  webhook_path_key          text,
  webhook_secret_encrypted  text,
  is_active                 boolean     not null default true,
  verified_at               timestamptz,
  verified_by               text,
  verification_error        text,
  created_at                timestamptz not null default now(),
  created_by                text,
  updated_at                timestamptz not null default now(),
  updated_by                text,
  primary key (company_id, provider),
  constraint provider_credentials_environment_chk
    check (environment in ('sandbox','production')),
  -- AP's public key starts pub_ and its private key starts api_. The public
  -- key is handed to the buyer's browser by four prepare actions, so a
  -- private key pasted into that field publishes the roaster's gateway
  -- credentials to every storefront visitor. The app validates it; this is
  -- the backstop a future writer cannot skip.
  constraint provider_credentials_public_key_chk
    check (provider <> 'activitypay' or public_key like 'pub\_%'),
  constraint provider_credentials_last4_chk
    check (secret_key_last4 is null or char_length(secret_key_last4) <= 4)
);

comment on table public.provider_credentials is
  'Per-tenant payment gateway credentials. Activity Pay is the PayFac and each roaster has their own merchant account; STRATA drives it on their behalf and is not in the money flow. Secrets are AES-256-GCM envelopes under PROVIDER_CREDENTIAL_KEY, base64 text, written and read only with the service role.';
comment on column public.provider_credentials.secret_key_encrypted is
  'api_*** private key, sealed with lib/crypto/envelope purpose provider-credential. Never granted to anon or authenticated.';
comment on column public.provider_credentials.webhook_secret_encrypted is
  'The signature secret AP generated for this merchant''s webhook, sealed the same way.';
comment on column public.provider_credentials.webhook_path_key is
  'Opaque key in the roaster''s webhook URL. It selects which row to load and authenticates nothing: the HMAC still decides.';
comment on column public.provider_credentials.merchant_name is
  'What AP called the account when we last checked it, e.g. MAUI COFFEE ROASTERS.';
comment on column public.provider_credentials.verification_error is
  'Why the last re-check against Activity Pay failed. Cleared on a successful check and on a fresh save. Without it, a connection that has quietly stopped working looks exactly like one nobody has checked lately.';

-- Two rows carrying the same merchant id is a contradiction, and the webhook
-- receiver resolves a tenant by exactly one of these two values with
-- maybeSingle. A duplicate must error, never resolve to a guess.
create unique index if not exists provider_credentials_merchant_uniq
  on public.provider_credentials (provider, merchant_id) where merchant_id is not null;
create unique index if not exists provider_credentials_webhook_path_uniq
  on public.provider_credentials (webhook_path_key) where webhook_path_key is not null;

create or replace function public.trg_set_provider_credentials_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end;
$$;

drop trigger if exists set_provider_credentials_updated_at on public.provider_credentials;
create trigger set_provider_credentials_updated_at
  before update on public.provider_credentials
  for each row execute function public.trg_set_provider_credentials_updated_at();

alter table public.provider_credentials enable row level security;

-- Read only, and only your own company's row. Every write goes through a
-- server action gated on payments.credentials_manage and executed with the
-- service role: a tenant member with direct PostgREST write access here could
-- point their company at another roaster's merchant id or swap a key, and RLS
-- cannot tell that apart from legitimate self-service.
drop policy if exists tenant_company_read on public.provider_credentials;
create policy tenant_company_read on public.provider_credentials
  for select to authenticated
  using (company_id in (select auth_company_ids()));

-- Column grants, not a table grant. Postgres cannot revoke a single column
-- out of a table-level grant, so the table grant goes first and the readable
-- columns are named one by one. Neither encrypted column is in that list, so
-- no signed-in user can read a gateway secret over PostgREST however the
-- policy is written. NOTE the tripwire this creates on purpose: an
-- authenticated `select=*` against this table now errors. Tenant-facing code
-- names its columns, or calls readApCredentialSummary().
revoke all on public.provider_credentials from anon, authenticated;
grant select (company_id, provider, environment, public_key, secret_key_last4,
              merchant_id, merchant_name, webhook_path_key, is_active,
              verified_at, verified_by, verification_error,
              created_at, created_by, updated_at, updated_by)
  on public.provider_credentials to authenticated;
grant all on public.provider_credentials to service_role;

commit;
