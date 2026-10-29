-- The payment page has a baseline, so a change to it can be noticed.
--
-- PCI 6.4.3 wants three things for every script that runs on a payment page:
-- (a) a method confirming the script is authorized, (b) a method assuring its
-- integrity, (c) a maintained inventory with written justification. 11.6.1
-- wants change- and tamper-detection on payment pages' HTTP headers AND
-- content. Both are currently unmet. This table is the part that has to
-- survive a deploy: what we last saw, so the next check can tell whether it
-- moved.
--
-- ── Why not SRI, which is the obvious answer to (b) ──────────────────────
--
-- The card form loads `${baseUrl}/tokenizer/tokenizer.js`, where baseUrl comes
-- from the TENANT'S OWN credentials at runtime, so different tenants load
-- different origins. Measured today, both are live and they are not the same
-- file: app.activitypaygateway.co serves 16,090 bytes, sandbox serves 16,098.
--
-- 🔴 It is the PROCESSOR'S file. Pinning a Subresource Integrity hash to a
-- vendor script we do not control means checkout dies, silently and for
-- everyone, the morning they ship an update. 6.4.3 explicitly accepts a
-- documented inventory plus change detection as the alternative, and that is
-- the route taken here. This is a decision, not an omission.
--
-- ── What this can honestly detect, and what it cannot ────────────────────
--
-- Measured before designing it: both payment routes return 307 to
-- `/{slug}/login`, because the pay page is reached either by a signed-in buyer
-- or by `?t={pay_token}` on an emailed invoice. So an unauthenticated checker
-- cannot fetch the card form's own HTML.
--
-- It CAN fetch, and therefore does:
--   · every third-party script's BODY, hashed -- the actual 6.4.3(b) subject,
--     and the only part an attacker can change without touching our deploy.
--   · the payment routes' HTTP RESPONSE HEADERS, hashed -- which is literally
--     what 11.6.1 names first, and the 307 still carries every one of them
--     (CSP, HSTS, X-Frame-Options, nosniff, Referrer-Policy,
--     Permissions-Policy). A widened CSP script-src is exactly the drift worth
--     an alert.
-- It CANNOT fetch the authenticated page's body. That is covered differently
-- rather than pretended: our own page content changes only when we deploy, so
-- each row records the `build_id` it was observed under. Content drift with an
-- unchanged build id would be the alarming case, and a changed build id
-- explains it.
--
-- ── Shape ────────────────────────────────────────────────────────────────
--
-- One row per thing watched, carrying both the EXPECTATION and the last
-- observation. `sha256` is the baseline; a run that sees a different digest
-- raises and then updates it, so an alert fires once per change rather than
-- every hour forever. `justification` is the 6.4.3(c) requirement and is why
-- the column is NOT NULL -- an inventory without a written reason for each
-- entry does not satisfy the clause, and a nullable column is an invitation to
-- leave it empty.

begin;

create table if not exists public.payment_page_baseline (
  id            uuid primary key default gen_random_uuid(),
  -- 'script' = a file fetched and hashed; 'headers' = a route's response headers
  kind          text not null check (kind in ('script', 'headers')),
  -- the absolute URL of the script, or the payment route path
  target        text not null,
  -- 6.4.3(c): WHY this script is on a payment page. Not nullable on purpose.
  justification text not null,
  -- 6.4.3(a): authorized by whom, and when. A script present but not
  -- authorized is the finding; this column is what makes "authorized" a fact
  -- rather than an assumption.
  authorized_by text not null,
  sha256        text,
  byte_size     integer,
  build_id      text,
  first_seen_at timestamptz,
  last_seen_at  timestamptz,
  last_checked_at timestamptz,
  -- a target we expect to EXIST. false for one we deliberately keep in the
  -- inventory as known-and-not-on-a-payment-page (reCAPTCHA), so the
  -- inventory is complete without the checker alerting on its absence.
  expect_present boolean not null default true,
  drift_count   integer not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (kind, target)
);

comment on table public.payment_page_baseline is
  'PCI 6.4.3 + 11.6.1: the authorized script inventory for payment pages, with each entry''s justification, plus the last observed digest so a change can be detected. Written by /api/cron/payment-integrity.';

-- 🔴 RLS on with ZERO policies, deliberately. This is PLATFORM data, not tenant
-- data: there is no company_id to scope by and no role that should read it from
-- the app. In Postgres, RLS enabled with no policy denies everything to a
-- non-owner, so `authenticated` and `anon` get nothing -- which is the whole
-- intent. The cron writes it with the service role and the /dev page reads it
-- with the admin client, both of which bypass RLS.
--
-- So this feature ships NO permission key, and that is the considered answer to
-- the standing "every new feature ships its role + plan permissions" rule
-- rather than an oversight: there is no user-facing capability here to grant.
alter table public.payment_page_baseline enable row level security;

-- And no write privilege either, so a future permissive policy cannot hand it
-- out by accident. Belt and braces, the same direction as 20261028000017.
revoke all on public.payment_page_baseline from authenticated, anon;

create index if not exists idx_payment_page_baseline_kind on public.payment_page_baseline (kind);

-- updated_at, using the house trigger rather than a new spelling of it.
drop trigger if exists trg_payment_page_baseline_updated_at on public.payment_page_baseline;
create trigger trg_payment_page_baseline_updated_at
  before update on public.payment_page_baseline
  for each row execute function public.handle_updated_at_timestamp();

do $$
declare n int; pol int; has_auth boolean;
begin
  select count(*) into n from pg_class c join pg_namespace s on s.oid=c.relnamespace
   where s.nspname='public' and c.relname='payment_page_baseline' and c.relrowsecurity;
  if n <> 1 then raise exception 'payment_page_baseline does not have RLS enabled'; end if;

  select count(*) into pol from pg_policies
   where schemaname='public' and tablename='payment_page_baseline';
  if pol <> 0 then
    raise exception 'payment_page_baseline has % policy(ies); it is meant to have none so RLS denies all', pol;
  end if;

  -- the deny must be real, not inferred from the absence of a policy
  select has_table_privilege('authenticated','public.payment_page_baseline','SELECT')
      or has_table_privilege('authenticated','public.payment_page_baseline','INSERT')
      or has_table_privilege('anon','public.payment_page_baseline','SELECT')
    into has_auth;
  if has_auth then
    raise exception 'authenticated or anon still holds a privilege on payment_page_baseline';
  end if;

  raise notice 'payment_page_baseline is ready: platform-only, RLS on with no policies, no grants to authenticated or anon';
end $$;

commit;
