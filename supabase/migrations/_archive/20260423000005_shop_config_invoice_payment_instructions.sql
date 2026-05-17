-- Sprint 7: payment instructions for net-terms invoices.
--
-- Free-text block the roaster fills in once on /shop and we render in the PDF
-- footer (e.g. "Mail check to PO Box 123 / ACH routing 1234 acct 5678 /
-- Email roast@bobscoffee.com to set up Bill.com"). Optional — when blank, the
-- invoice falls back to "Reply to this email for payment instructions."
--
-- Single column, additive, no backfill needed.

ALTER TABLE public.shop_config
  ADD COLUMN IF NOT EXISTS invoice_payment_instructions text;

COMMENT ON COLUMN public.shop_config.invoice_payment_instructions IS
  'Free-text payment instructions rendered in the footer of net-terms invoice PDFs. NULL/empty falls back to a generic reply-to-email blurb.';
