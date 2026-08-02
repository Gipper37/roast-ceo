-- The "c/o" line QuickBooks has and STRATA didn't.
--
-- 🔴 WHAT IT LOOKS LIKE. Aloha Boba Co.'s shipping address reads:
--     Address            Sara Phelan
--     Apt, suite, unit   66-456 Kameahameaha Hwy.
--     City               Haleiwa
-- A person's name sitting in the street field, with the actual street demoted to
-- the apartment line. Every label, packing slip and invoice built from that
-- address is wrong, and the apartment field is unusable for what it is for.
--
-- CAUSE. A QuickBooks address block is free-form lines under the company name:
--     Aloha Boba Co.
--     Sara Phelan                 <- attention / c-o line
--     66-456 Kameahameaha Hwy.
--     Haleiwa, HI 96712
-- QB exports those as Street1/Street2, so Street1 is the ATTENTION line whenever
-- there is one and the STREET when there isn't. The importer copied Street1 →
-- street and Street2 → street_2 unconditionally, which is right half the time.
-- STRATA had nowhere else to put a name, so nothing could have been right.
--
-- Adds a real attention line per address, then corrects what is already stored.
--
-- THE BACKFILL RULE, deliberately narrow: shift ONLY when line 1 does NOT look
-- like a street AND line 2 DOES (starts with a digit, or a PO Box in any of its
-- spellings). So:
--   "Sara Phelan" + "66-456 Kameahameaha Hwy."  → shifted. Unambiguous.
--   "Maui Fire Department" + (nothing)          → untouched. There is no street
--     to promote; that record is simply missing its street, a different problem.
--   "Store # 251500" + "P O BOX 29083"          → shifted. A store number is an
--     attention line, and case-insensitive matching catches the PO Box.
--   "175 Kapuahi St." + …                       → untouched, already correct.
--
-- Counted against prod before writing: shipping 71 to shift / 251 already right
-- / 34 with no street to promote. Billing 81 / 245 / 35.

begin;

alter table public.customers
  add column if not exists ship_attention text,
  add column if not exists bill_attention text;

comment on column public.customers.ship_attention is
  'Attention / c-o line for the shipping address — a person or department the delivery is for. QuickBooks calls this the first free-form line of the address block; it is NOT part of the street.';
comment on column public.customers.bill_attention is
  'Attention / c-o line for the billing address. See ship_attention.';

-- A line that begins with a house number or a PO Box is a street. Anything else
-- sitting above a real street is an attention line.
create or replace function pg_temp.looks_like_street(v text) returns boolean
language sql immutable as $$
  select coalesce(v ~* '^\s*(\d|p\.?\s*o\.?\s*box)', false)
$$;

-- ── Shipping ──
update public.customers
   set ship_attention = btrim(street),
       street         = btrim(street_2),
       street_2       = null
 where ship_attention is null
   and street is not null and street_2 is not null
   and not pg_temp.looks_like_street(street)
   and     pg_temp.looks_like_street(street_2);

-- ── Billing ──
update public.customers
   set bill_attention   = btrim(billing_address),
       billing_address  = btrim(billing_address_2),
       billing_address_2 = null
 where bill_attention is null
   and billing_address is not null and billing_address_2 is not null
   and not pg_temp.looks_like_street(billing_address)
   and     pg_temp.looks_like_street(billing_address_2);

commit;

notify pgrst, 'reload schema';
