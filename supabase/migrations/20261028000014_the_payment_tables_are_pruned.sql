-- The payment tables are in the prune job, and the card expiry ages out.
--
-- ── What was true ────────────────────────────────────────────────────────
--
-- The nightly prune covered exactly four tables -- roast_smartroast_log,
-- client_telemetry_events, server_error_events, staged_shipments -- and no
-- payment table was among them. Read from the LIVE function body, not a
-- migration file.
--
-- payment_webhook_events has an UNAUTHENTICATED writer: /api/webhooks is a
-- public path, and the bare endpoint's secret candidates always include the
-- platform env key, so any anonymous POST carrying any Signature header and a
-- sub-64KiB body lands a row. The BODY was capped from the start. The ROW
-- COUNT never was, and nothing ever deleted one.
--
-- ── What is actually stored, measured ────────────────────────────────────
--
-- 🔴 The audit implied prohibited data. There is none. Searched both tables,
-- nested as well as top level: first_six, last_four, masked_card,
-- expiration_date, card_type, cvv_response_code -- at
-- data -> response_body -> card. No CVV, no CAVV, no XID, no track data.
--
-- first_six + last_four + masked_card are a PERMITTED truncation, and
-- cvv_response_code is the RESULT of the check ("M"), not the code. So this is
-- a retention trim and not a breach clean-up, and it keeps those on purpose:
-- support needs "the Visa ending 1111" long after an expiry date stops
-- mattering. The expiry is the one with no lasting purpose, because saved
-- cards live in the gateway vault behind a token and our copy is historical.
--
-- Today: 9 webhook rows (7 with a bad signature, all 2026-07-28) and 1
-- transaction, which is a 411111 test card. Nearly empty -- which is exactly
-- why now, before the live-payment test fills them.
--
-- ── The windows, and why they differ ─────────────────────────────────────
--
--   bad signature, 30 days   a diagnostic, useful for days not years
--   processed, 365 days      a financial record
--   verified but UNPROCESSED never deleted by age -- that is work nobody has
--                            done yet, and ageing it out would silently drop a
--                            settlement or a refund
--   card expiry, 180 days    stripped from raw_response, the permitted fields kept
--
-- Body taken from pg_get_functiondef on production and patched.

begin;

CREATE OR REPLACE FUNCTION public.prune_append_only_tables()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_smartroast bigint;
  v_telemetry  bigint;
  v_errors     bigint;
  v_staged     bigint;
  v_hooks      bigint;
  v_stripped   bigint;
begin
  delete from public.roast_smartroast_log where created_at < now() - interval '365 days';
  get diagnostics v_smartroast = row_count;

  delete from public.client_telemetry_events where created_at < now() - interval '90 days';
  get diagnostics v_telemetry = row_count;

  delete from public.server_error_events where created_at < now() - interval '90 days';
  get diagnostics v_errors = row_count;

  -- A confirmed staged shipment is the receipt for inventory that exists. Only
  -- the abandoned ones age out; staged_line_items cascade.
  delete from public.staged_shipments
   where status is distinct from 'confirmed'
     and coalesce(updated_at, created_at) < now() - interval '90 days';
  get diagnostics v_staged = row_count;

  -- ── payment_webhook_events ───────────────────────────────────────────
  -- 🔴 THIS TABLE HAS AN UNAUTHENTICATED WRITER. /api/webhooks is a public
  -- path and the bare endpoint's secret candidates always include the platform
  -- env key, so any anonymous POST with any Signature header and a sub-64KiB
  -- body lands a row. The body was capped from the start; the ROW COUNT never
  -- was, and this table was in no prune job at all.
  --
  -- Measured before writing this: 9 rows, 7 of them signature_valid = false,
  -- all from 2026-07-28. Not a mess today -- which is the point of doing it
  -- now, before the live-payment test starts filling it.
  --
  -- Split by what the row IS, not by one age:
  --   a failed signature is a diagnostic, useful for days, not years
  --   a processed event is a financial record and keeps a year
  --   a VERIFIED but UNPROCESSED event is work that has not happened yet and
  --   is never deleted by age -- deleting it would silently drop a settlement
  --   or a refund nobody handled.
  delete from public.payment_webhook_events
   where (signature_valid = false and received_at < now() - interval '30 days')
      or (processed = true      and received_at < now() - interval '365 days');
  get diagnostics v_hooks = row_count;

  -- ── Card data retention (PCI 3.2.1) ──────────────────────────────────
  -- 🔴 WHAT IS ACTUALLY STORED, measured rather than assumed: first_six,
  -- last_four, masked_card, expiration_date, card_type and cvv_response_code,
  -- at data -> response_body -> card. NOTHING PROHIBITED IS PRESENT -- no CVV,
  -- no CAVV, no XID, no track data. first_six + last_four + masked_card are a
  -- PERMITTED truncation, and cvv_response_code is the RESULT of the check
  -- ("M"), not the code itself. So this is a retention trim, not a breach
  -- clean-up, and it deliberately keeps the permitted fields: support needs
  -- "the Visa ending 1111" long after the expiry stops mattering.
  --
  -- The expiry is the one with no lasting purpose here: saved cards live in
  -- the gateway's vault behind a token, so our copy is historical only.
  update public.payment_transactions
     set raw_response = raw_response #- '{data,response_body,card,expiration_date}'
   where created_at < now() - interval '180 days'
     and raw_response #> '{data,response_body,card,expiration_date}' is not null;
  get diagnostics v_stripped = row_count;

  raise notice 'pruned: smartroast=% telemetry=% errors=% staged_shipments=% webhook_events=% card_expiry_stripped=%',
    v_smartroast, v_telemetry, v_errors, v_staged, v_hooks, v_stripped;
end
$function$;

do $$
declare v_src text;
begin
  select prosrc into v_src from pg_proc
   where proname = 'prune_append_only_tables' and pronamespace = 'public'::regnamespace;

  if v_src not like '%payment_webhook_events%' then
    raise exception 'the prune still does not cover payment_webhook_events';
  end if;
  if v_src not like '%expiration_date%' then
    raise exception 'the prune still does not age out the card expiry';
  end if;

  -- 🔴 The four it already covered must survive. This widens the job; it does
  -- not replace it.
  if v_src not like '%roast_smartroast_log%' or v_src not like '%client_telemetry_events%'
     or v_src not like '%server_error_events%' or v_src not like '%staged_shipments%' then
    raise exception 'the prune lost one of the four tables it already covered';
  end if;

  -- 🔴 And a verified-but-unprocessed event must NOT be deletable by age.
  -- Asserted on the TEXT because the delete is conditional and cannot be
  -- exercised without rows; if someone later simplifies this to one age, the
  -- release fails here instead of quietly dropping an unhandled settlement.
  if v_src not like '%processed = true%' then
    raise exception 'the webhook prune no longer distinguishes processed events';
  end if;

  raise notice 'the payment tables are pruned and the card expiry ages out; the four original tables are untouched';
end $$;

commit;
