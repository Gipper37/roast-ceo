-- A wholesale access request is a thing you can answer.
--
-- The storefront's request form sent an email and wrote a row to email_log with
-- event_type 'wholesale_request', and that was the whole mechanism. Its own
-- comment said so: "Always log even if we can't email -- operator can mine
-- email_log later." There was no request to approve, no state, and nothing to
-- surface, which is why the email carried no approve link and nothing appeared
-- anywhere in the app.
--
-- Owner, 2026-10-02: "why can't a user approve that request from a link in the
-- email and why aren't those surfaced somwhere on the site as todos or
-- something urgent looking."
--
-- TWO ARE OUTSTANDING ON PROD RIGHT NOW, both MCR, and they are carried over
-- rather than lost:
--   2026-10-02  Colleen Nicholas, Colleen's At The Cannery
--   2026-10-03  Nadia Toraman, Island Fresh Cafe
--
-- NO NEW PERMISSION KEY. Answering a request grants a tier and sends an
-- invitation, which is exactly the authority shop.customer_invite already
-- carries. A second key over one action is the failure 20260926000014 and
-- 20260929000003 were both written to undo.
--
-- approve_token exists so the email can carry a link that identifies the
-- request without naming a row id, the same shape as orders.pay_token. It is
-- not an authorization on its own: the action behind it still requires a signed
-- in operator holding shop.customer_invite. The link saves a search, it does
-- not replace a login.
--
-- status is text with a CHECK rather than an enum, matching every other state
-- column in this schema (invoice_state, order_status), so adding a state later
-- is a migration and not a type rewrite.

begin;

create table if not exists public.shop_access_request (
  request_id     text primary key default (gen_random_uuid())::text,
  company_id     text not null references public.companies(company_id),
  slug           text,
  name           text not null,
  email          text not null,
  business       text,
  phone          text,
  message        text,
  -- The customer this turned out to be, once somebody decides. Null while
  -- pending, and null forever on a request from someone who never becomes one.
  customer_id    text references public.customers(customer_id),
  status         text not null default 'pending'
                 check (status in ('pending', 'approved', 'declined')),
  approve_token  text not null default (gen_random_uuid())::text,
  decided_at     timestamptz,
  decided_by     text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  created_by     text,
  updated_by     text,
  -- A decision has a time and a hand behind it; pending has neither.
  constraint shop_access_request_decided_together
    check ((status = 'pending') = (decided_at is null))
);

comment on table public.shop_access_request is
  'Someone asking for wholesale access through the storefront. Answering one grants a tier and sends an invitation, so it is gated on shop.customer_invite.';

create unique index if not exists shop_access_request_token_uidx
  on public.shop_access_request (approve_token);

-- The todo list: pending first, newest first, per company.
create index if not exists shop_access_request_company_status_idx
  on public.shop_access_request (company_id, status, created_at desc);

alter table public.shop_access_request enable row level security;

-- Mirrors customer_users: the roaster's own company and nothing else. The
-- storefront form writes through the admin client, as every other public shop
-- path does, so there is deliberately no anon policy -- an anonymous INSERT
-- policy here would let anyone fill this table from outside.
drop policy if exists roaster_manage_shop_access_request on public.shop_access_request;
create policy roaster_manage_shop_access_request
  on public.shop_access_request
  for all
  to authenticated
  using  (company_id in (select public.auth_company_ids()))
  with check (company_id in (select public.auth_company_ids()));

grant select, insert, update on public.shop_access_request to authenticated;

-- What was already asked, carried over from the email log so neither roaster
-- loses a lead to this change.
insert into public.shop_access_request
  (company_id, slug, name, email, business, phone, message, created_at)
select el.company_id,
       el.metadata->>'slug',
       coalesce(el.metadata->>'name', el.to_email),
       el.to_email,
       el.metadata->>'business',
       el.metadata->>'phone',
       el.metadata->>'message',
       el.sent_at
  from public.email_log el
 where el.event_type = 'wholesale_request'
   and not exists (
     select 1 from public.shop_access_request r
      where r.company_id = el.company_id and lower(r.email) = lower(el.to_email)
   );

do $verify$
declare v_bad int; v_n int;
begin
  select count(*) into v_n from public.shop_access_request;
  if v_n < 2 then
    raise exception 'expected the 2 outstanding requests to carry over, found %', v_n;
  end if;

  -- Every carried-over request is answerable: pending, with a token.
  select count(*) into v_bad from public.shop_access_request
   where status <> 'pending' or approve_token is null or email is null;
  if v_bad > 0 then raise exception '% carried-over request(s) are not answerable', v_bad; end if;

  -- Tokens are unique, or one link would answer somebody else's request.
  select count(*) into v_bad from (
    select approve_token from public.shop_access_request group by 1 having count(*) > 1) t;
  if v_bad > 0 then raise exception '% duplicate approve token(s)', v_bad; end if;

  -- 🔴 RLS is on and there is no anon policy. Without this the form's own table
  -- would be writable from outside by anyone who found it.
  if not exists (select 1 from pg_class where relname='shop_access_request' and relrowsecurity) then
    raise exception 'row level security is not enabled';
  end if;
  select count(*) into v_bad from pg_policies
   where schemaname='public' and tablename='shop_access_request'
     and ('anon' = any(roles) or 'public' = any(roles));
  if v_bad > 0 then raise exception '% policy(ies) expose this table to anon', v_bad; end if;

  -- No new permission key was minted; the existing one still exists to gate it.
  if not exists (select 1 from public.permissions where permission_id='shop.customer_invite') then
    raise exception 'shop.customer_invite is missing; the gate for answering a request is gone';
  end if;
end;
$verify$;

commit;
