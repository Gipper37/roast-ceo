-- A posted invoice with no address may have the one its payer confirmed written in.
--
-- 🔴 THE HOLE. The pay page asks for a billing address, sends it to the gateway,
-- and then writes it to the order, so that the receipt at /[slug]/order/[ref] has
-- something to print. That write has never landed. A payable invoice is posted by
-- definition (invoice_ar_balances is `WHERE o.posted`), and
-- guard_posted_order_immutable locks all nine bill_to_* columns, so every attempt
-- raised 'its document fields are locked', the action logged it because the money
-- had already moved, and the receipt went on saying "Not provided". Measured on
-- staging as the service role, the client that action uses: P0001.
--
-- WHY THE LOCK AND THE WRITE DO NOT ACTUALLY DISAGREE. The lock exists so a document
-- a customer has been handed cannot be quietly edited. An order with no address has
-- no address to protect: its invoice prints whatever the customer record says on the
-- day it is opened, so it is the blank that floats, not the fill.
--
-- WHAT IS STILL REFUSED, every one of them rehearsed on staging:
--   * Anything with a JWT. Every signed-in role, including the company admin. Nothing
--     on the staff side asks for this, so the door is not offered to it. The caller is
--     the pay action, on the service role; `auth.uid() IS NULL` is the same test
--     guard_order_invoice_columns and guard_demo_readonly open with.
--   * An order that already holds any part of an address. That is what stops a splice:
--     filling only the blank lines of a half-address would pair a ZIP from one address
--     with the street of another, and a family is selected whole (see
--     lib/payments/billingPrefill in the frontend). bill_to_address_2 counts, so a lone
--     suite number closes the door as well.
--   * A partial fill. Street, city, state and ZIP all arrive or none do. They are the
--     same four billingMissing makes the charge require, so the caller always has them,
--     and a street alone would slam this door on an address nobody could finish.
--   * Rewriting a name, email or phone the order already holds. Those stand apart from
--     the address, so an order with only a contact on it can still be filled, and they
--     may go from blank to something. bill_to_country is the exception and may change,
--     because addressColumnSlice stamps 'US' on every storefront order whether or not
--     an address came with it: on an order with no street it is a default, not a fact.
--   * Every other locked column, even in the same statement as a fill: this sits
--     inside its own OR, so tax, discount, number and customer are refused as before.
--
-- Function text taken from staging's pg_get_functiondef; only the nine bill_to lines
-- moved. btrim because a blank string is as empty as a NULL: the storefront writes
-- NULLs, but the guard is the wrong place to assume every writer always will.

CREATE OR REPLACE FUNCTION public.guard_posted_order_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.posted THEN
      RAISE EXCEPTION 'order % is a posted invoice and cannot be deleted — void it instead', OLD.order_id;
    END IF;
    RETURN OLD;
  END IF;

  IF OLD.posted THEN
    IF (NEW.customer_id      IS DISTINCT FROM OLD.customer_id)
    OR (NEW.order_date       IS DISTINCT FROM OLD.order_date)
    OR (NEW.tax_amount       IS DISTINCT FROM OLD.tax_amount)
    OR (NEW.tax_rate         IS DISTINCT FROM OLD.tax_rate)
    OR (NEW.tax_rate_id        IS DISTINCT FROM OLD.tax_rate_id)
    OR (NEW.tax_basis          IS DISTINCT FROM OLD.tax_basis)
    OR (NEW.prices_include_tax IS DISTINCT FROM OLD.prices_include_tax)
    OR (NEW.tax_passed_through IS DISTINCT FROM OLD.tax_passed_through)
    OR (NEW.discount_kind    IS DISTINCT FROM OLD.discount_kind)
    OR (NEW.discount_value   IS DISTINCT FROM OLD.discount_value)
    OR (NEW.discount_total   IS DISTINCT FROM OLD.discount_total)
    OR (NEW.invoice_number   IS DISTINCT FROM OLD.invoice_number)
    OR (NEW.invoice_sequence IS DISTINCT FROM OLD.invoice_sequence)
    OR (
      (   (NEW.bill_to_name     IS DISTINCT FROM OLD.bill_to_name)
       OR (NEW.bill_to_address  IS DISTINCT FROM OLD.bill_to_address)
       OR (NEW.bill_to_address_2 IS DISTINCT FROM OLD.bill_to_address_2)
       OR (NEW.bill_to_city     IS DISTINCT FROM OLD.bill_to_city)
       OR (NEW.bill_to_state    IS DISTINCT FROM OLD.bill_to_state)
       OR (NEW.bill_to_zip      IS DISTINCT FROM OLD.bill_to_zip)
       OR (NEW.bill_to_country  IS DISTINCT FROM OLD.bill_to_country)
       OR (NEW.bill_to_email    IS DISTINCT FROM OLD.bill_to_email)
       OR (NEW.bill_to_phone    IS DISTINCT FROM OLD.bill_to_phone)
      )
      -- The one way in: no JWT, an order holding no address, a whole address
      -- arriving, and any contact the order already holds left as it is. Once
      -- this has fired the order holds an address, so it can only fire once.
      AND NOT (
            auth.uid() IS NULL
        AND nullif(btrim(OLD.bill_to_address), '')   IS NULL
        AND nullif(btrim(OLD.bill_to_address_2), '') IS NULL
        AND nullif(btrim(OLD.bill_to_city), '')      IS NULL
        AND nullif(btrim(OLD.bill_to_state), '')     IS NULL
        AND nullif(btrim(OLD.bill_to_zip), '')       IS NULL
        AND nullif(btrim(NEW.bill_to_address), '')   IS NOT NULL
        AND nullif(btrim(NEW.bill_to_city), '')      IS NOT NULL
        AND nullif(btrim(NEW.bill_to_state), '')     IS NOT NULL
        AND nullif(btrim(NEW.bill_to_zip), '')       IS NOT NULL
        AND (nullif(btrim(OLD.bill_to_name), '')  IS NULL OR NEW.bill_to_name  IS NOT DISTINCT FROM OLD.bill_to_name)
        AND (nullif(btrim(OLD.bill_to_email), '') IS NULL OR NEW.bill_to_email IS NOT DISTINCT FROM OLD.bill_to_email)
        AND (nullif(btrim(OLD.bill_to_phone), '') IS NULL OR NEW.bill_to_phone IS NOT DISTINCT FROM OLD.bill_to_phone)
      )
    )
    THEN
      RAISE EXCEPTION 'order % is a posted invoice — its document fields are locked (void-and-reissue or issue a credit memo to change it)', OLD.order_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;
