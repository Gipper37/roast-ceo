-- A customer may have more than one inbox.
--
-- Owner, 2026-11-16: "i just wanted you to add the ability for multiple
-- notification emails to be input to a customer detail page. just below the
-- main email. then, whenever an invoice is or accounting related email is sent
-- then it sends to those emails also."
--
-- and then, asked whether the field should say "accounting notifications":
-- "probably just notification emails. and then we will send any notification
-- related to that customer (aside from logins obviously)."
--
-- So this is not an accounting column. It is WHO THIS CUSTOMER IS REACHED AT,
-- for every notification about them, and the only exception is a credential:
-- the storefront invite and the invoice-account magic link stay one person's.
--
-- Today every accounting document goes to exactly ONE address.
-- `lib/shop/invoiceDispatch.ts` resolves
-- `order.bill_to_email ?? order.ship_to_email ?? customers.email` and sends
-- `to: [payload.buyer.email]`; both per-order columns hold 0 rows on prod, so
-- in practice the address is always `customers.email`, singular. One customer
-- has already worked around it by typing two addresses into that one column
-- (Seven Brothers, `f2q53ebu`) -- which Resend rejects, so that customer has
-- never received anything: 0 email_log rows.
--
-- 🔴 THIS IS A COLUMN ON THE CUSTOMER, NOT A FLAG ON `contacts`, and the
-- difference is not cosmetic. `contact.view` / `contact.edit` are granted to
-- the pro, enterprise and enterprise_plus plans only, so a contacts-based
-- answer is invisible to a starter tenant. `customer.edit` includes starter.
-- An A/P inbox is also usually not a person: "ap@", "invoices@", a shared
-- mailbox. Making the roaster invent a contact record to hold one is work for
-- nothing, and two ways to name the same recipient is how a floor gets
-- confused about which one is live.
--
-- NOT the login. The storefront login is `customer_users.email`, written from
-- the accepted invite (`app/api/shop-invite/accept/route.ts:131`).
-- `customers.email` is the billing and orders address, and nothing here can
-- affect who can sign in.

begin;

set local lock_timeout = '3s';
set local statement_timeout = '60s';

alter table public.customers
  add column if not exists notification_emails text[] not null default '{}';

comment on column public.customers.notification_emails is
  'Extra addresses that also receive every notification about this customer: invoices, receipts, payment confirmations, order confirmations, order status, reorder reminders, recall notices, equipment maintenance reminders and resale certificate requests. The address in `email` is the primary and always receives them; these are in addition, each as its own message so a bounce can be told apart. NEVER a login: the storefront invite and the invoice-account magic link are one person''s credential and are not copied here.';

-- A cap, because every address is one more message per document and the fan-out
-- runs inside a bulk send that already walks the invoices one at a time. Ten is
-- past any real A/P department and well short of a paste accident.
alter table public.customers
  drop constraint if exists customers_notification_emails_capped;
alter table public.customers
  add constraint customers_notification_emails_capped
  check (coalesce(array_length(notification_emails, 1), 0) <= 10);

-- 🔴 THE BOUNCE FLAG MUST STAY ABOUT THE CUSTOMER'S OWN ADDRESS.
--
-- `trg_flag_customer_on_email_bounce` fires AFTER UPDATE OF status on
-- email_log and stamps `customers.email_bounced_at` for the customer named by
-- `email_log.customer_id`. The app now writes ONE email_log row per recipient,
-- so without this change a bouncing "ap@" address would mark the CUSTOMER as
-- bouncing -- whose own address is fine. `customers/page.tsx:360` counts that
-- as a bouncing customer and `AccountManagementClient.tsx:434` shows the
-- warning against the customer's own address, offering "update the address to
-- clear" -- which would have the roaster retyping the wrong one.
--
-- The sender is the authority on which copy is which, so it says so in
-- `metadata.recipient_kind` and this reads it. A row that does not say is
-- treated as the customer's own, which is what every row written before today
-- is, so existing behaviour is preserved exactly.
--
-- The body below is the deployed one, read out of pg_proc rather than retyped,
-- with one condition added to its guard.
create or replace function public.flag_customer_on_email_bounce()
 returns trigger
 language plpgsql
as $function$
BEGIN
  IF NEW.status IN ('bounced', 'complained')
     AND OLD.status IS DISTINCT FROM NEW.status
     AND NEW.customer_id IS NOT NULL
     AND COALESCE(NEW.metadata->>'recipient_kind', 'customer') = 'customer'
  THEN
    UPDATE public.customers
       SET email_bounced_at = COALESCE(email_bounced_at, NOW()),
           email_bounce_reason = COALESCE(
             NEW.metadata->>'bounce_reason',
             NEW.status
           )
     WHERE customer_id = NEW.customer_id
       AND email_bounced_at IS NULL;  -- don't overwrite an existing flag
  END IF;
  RETURN NEW;
END;
$function$;

do $$
declare
  v_src     text;
  v_notnull boolean;
  v_default text;
  v_type    text;
  v_tg      int2;
begin
  -- 1. The column exists, holds a list, cannot be null, and starts empty.
  select a.attnotnull, pg_get_expr(d.adbin, d.adrelid), format_type(a.atttypid, a.atttypmod)
    into v_notnull, v_default, v_type
  from pg_attribute a
  left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
  where a.attrelid = 'public.customers'::regclass
    and a.attname  = 'notification_emails'
    and a.attnum > 0 and not a.attisdropped;

  if v_notnull is null then
    raise exception 'customers.notification_emails was not created';
  end if;
  if v_type <> 'text[]' then
    raise exception 'customers.notification_emails is %, not text[]', v_type;
  end if;
  if not v_notnull then
    raise exception 'customers.notification_emails is nullable; every reader would need a null branch for what an empty list already says';
  end if;
  if coalesce(v_default, '') not like '%{}%' then
    raise exception 'customers.notification_emails does not default to the empty list (default is %)', coalesce(v_default, '<none>');
  end if;

  -- 2. The cap is real.
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.customers'::regclass
      and conname  = 'customers_notification_emails_capped'
  ) then
    raise exception 'customers_notification_emails_capped is missing; one paste could turn a single invoice into hundreds of messages';
  end if;

  -- 3. The bounce guard reads the sender's own answer, and still flags the
  --    customer -- a replacement that dropped either half would be silent.
  select p.prosrc into v_src
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'flag_customer_on_email_bounce';

  if v_src is null then
    raise exception 'flag_customer_on_email_bounce is gone';
  end if;
  if position('recipient_kind' in v_src) = 0 then
    raise exception 'flag_customer_on_email_bounce no longer checks recipient_kind, so a bouncing notification address will be stamped on the customer';
  end if;
  if position('UPDATE public.customers' in v_src) = 0 then
    raise exception 'flag_customer_on_email_bounce no longer flags the customer; the behaviour that existed before this migration has been lost';
  end if;

  -- 4. ...and it is still wired to the table, on UPDATE.
  select t.tgtype into v_tg
  from pg_trigger t
  where t.tgrelid = 'public.email_log'::regclass
    and t.tgname  = 'trg_flag_customer_on_email_bounce';

  if v_tg is null then
    raise exception 'trg_flag_customer_on_email_bounce is no longer attached to email_log';
  end if;
  if (v_tg & 1) = 0 then
    raise exception 'the bounce trigger is not FOR EACH ROW (tgtype %)', v_tg;
  end if;
  if (v_tg & 16) = 0 then
    raise exception 'the bounce trigger no longer fires on UPDATE (tgtype %); the webhook sets status by UPDATE', v_tg;
  end if;
end $$;

commit;
