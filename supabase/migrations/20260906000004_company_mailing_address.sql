-- A roastery's mailing address, for the footer of mail it sends its customers.
--
-- Nothing in the schema held one: companies has no address at all, and
-- facilities carries only country_code + time_zone. Anti-spam law (CAN-SPAM,
-- CASL, GDPR/PECR) requires a real postal address in the footer of commercial
-- mail, so the mass-email feature cannot send its first campaign without this.
-- Transactional mail (invoices, order status, reminders) is unaffected — it
-- has never needed one.
--
-- One free-text block rather than structured street/city/state/postal fields:
-- the only consumer renders it verbatim in a footer, roasteries outside the US
-- do not fit US address parts, and the operator pastes the block their letters
-- already use. Structured fields can be added later if something needs to sort
-- or validate an address; nothing does today.
--
-- Company-level, not facility-level: the legal sender of a marketing email is
-- the business, and a multi-facility roastery still has one mailing address.
-- Edited from Settings → Company under the existing company.edit permission —
-- no new permission key, because this is a field on a surface that already has
-- one, not a new capability.

begin;

alter table public.companies
  add column if not exists mailing_address text;

comment on column public.companies.mailing_address is
  'Postal address shown in the footer of customer-facing mail this roastery sends. Required before a marketing campaign can be sent; transactional mail does not use it.';

commit;
