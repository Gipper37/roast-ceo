-- Wholesale GET starts being grossed up. Forward only — history stays as billed.
--
-- MCR has charged a FLAT 0.5% on wholesale for seven years, which structurally
-- under-collects: Hawaii GET is owed on gross receipts, and the tax you collect
-- is itself part of those receipts. On the history now in STRATA that gap is
-- $52.15 — owed $11,122.51 against $11,070.36 collected. The owner has decided
-- to close it by grossing up, the way the retail rate already does.
--
-- The rule is simply: 0.5% OF THE GROSS. Because the gross includes the tax
-- itself, solving for it gives 0.5/99.5 = 0.502513% of the subtotal — the same
-- number reached from the other side, not a different rate:
--
--     0.502513% of $1,000.00 subtotal  = $5.03
--     0.5%      of $1,005.03 gross     = $5.03
--
-- The stored figure is the statutory 0.5% with gross_up set, and charge_rate is
-- derived. The label says "on the gross" rather than quoting 0.5025%, because
-- the operator should read the rule and not the algebra.
--
--     base  $1,000.00 x 0.502513%    = $5.03 charged
--     gross $1,000.00 + $5.03        = $1,005.03
--     filed $1,005.03 x 0.5%         = $5.03    collected == owed
--
-- ── WHY A NEW RATE AND NOT AN EDIT ───────────────────────────────────────────
-- 3,402 orders already point at mcr-hi-wholesale, and every one of them was
-- billed at the flat rate and matched to the QuickBooks invoice the customer
-- holds. Flipping gross_up on that row would change what those historical
-- invoices claim to have charged — the exact thing we spent two migrations
-- making sure could not happen.
--
-- So the flat rate is CLOSED as of today and a grossed-up successor opens
-- tomorrow. That is what effective dating is for, and the resolver already
-- picks by date. Old invoices keep pointing at the old rate and keep reporting
-- under it; new orders resolve to the new one. Nothing is restated.

begin;

update public.tax_rate
   set effective_to = current_date,
       label = 'GET wholesale 0.5% (flat, through ' || current_date || ')',
       updated_at = now()
 where tax_rate_id = 'mcr-hi-wholesale'
   and company_id = '9ShiyDAXhV'
   and effective_to is null;

insert into public.tax_rate
  (tax_rate_id, company_id, jurisdiction_id, code, label,
   statutory_rate, gross_up, kind, requires_resale_cert, filing_class, effective_from)
select 'mcr-hi-wholesale-gu', '9ShiyDAXhV', t.jurisdiction_id, 'GET_WHOLESALE_GU',
       'GET wholesale 0.5% on the gross',
       0.005, true, 'reduced', true, 'wholesaling', current_date + 1
  from public.tax_rate t
 where t.tax_rate_id = 'mcr-hi-wholesale'
on conflict (tax_rate_id) do nothing;

-- Point the live rules at the new rate. The rules are what new orders resolve
-- through; the closed rate stays reachable only by the orders already on it.
update public.tax_rule
   set tax_rate_id = 'mcr-hi-wholesale-gu', updated_at = now()
 where company_id = '9ShiyDAXhV'
   and tax_rate_id = 'mcr-hi-wholesale';

-- Same for any customer pinned directly to the flat rate.
update public.customers
   set tax_rate_id = 'mcr-hi-wholesale-gu'
 where company_id = '9ShiyDAXhV'
   and tax_rate_id = 'mcr-hi-wholesale';

commit;
