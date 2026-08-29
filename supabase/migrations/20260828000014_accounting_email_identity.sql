-- A designated accounting address for money email.
--
-- Two facts the owner ran into with one PO email to Royal Coffee:
--
--   The From line read "STRATA <roast@strataroast.com>" — the platform's name,
--   not the roaster's. A supplier or customer should see who is actually
--   writing to them.
--
--   Replies to an invoice have nowhere designated to go. MCR wants accounting
--   mail answered at an accounting address, not whichever operator's login sent
--   it.
--
-- The From ADDRESS must stay on STRATA's verified domain — DMARC forbids
-- sending as @mauicoffeeroasters.com without verifying their domain in Resend,
-- and a per-tenant domain program is its own project. What CAN carry the
-- roaster's identity today: the display name ("Maui Coffee Roasters via STRATA")
-- and the Reply-To. This column is that Reply-To for accounting mail: invoices,
-- payment confirmations, certificate requests, statements. NULL falls back to
-- the shop reply-to and then the sending operator, which is today's behaviour.

begin;

alter table public.billing_settings
  add column if not exists accounting_email text;

comment on column public.billing_settings.accounting_email is
  'Where replies to money email go — invoices, payment confirmations, resale '
  'certificate requests. NULL falls back to shop_config.reply_to_email. The From '
  'address stays on STRATA''s verified domain for deliverability; this and the '
  'display name are the roaster''s identity on the message.';

commit;
