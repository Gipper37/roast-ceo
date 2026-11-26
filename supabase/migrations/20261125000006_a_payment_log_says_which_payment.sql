-- An order's payment log has to say WHICH payment, or the page shows it twice.
--
-- `20261125000002` gave every order an activity log. Its reader also
-- RECONSTRUCTS history from the order's own columns for the orders that predate
-- the log, and drops a reconstructed row when the log already holds that event
-- KIND. That rule is right for the order columns, because each of them holds
-- only the LAST occurrence of its event. It is wrong for money:
-- `invoice_payment_allocations` is a LIST, so one order can hold several
-- payments, and "the log holds a payment_allocated" cannot say WHICH of them.
--
-- 🔴 SO EVERY PAYMENT TAKEN AFTER THAT MIGRATION LANDS WOULD RENDER TWICE --
-- once from the log, once reconstructed from the allocation -- as two identical
-- "Payment applied $500.00" lines on the one screen whose job is answering what
-- happened to the money. Caught in preflight before prod. Prod has no
-- `order_activity` table yet, so nothing is logged anywhere but staging.
--
-- The fix is one key. With the allocation's own id in the log row the reader
-- skips exactly the allocations the log covers and keeps the rest, so an order
-- with one logged payment and three older ones still shows all four. Keying on
-- the event KIND instead would erase the three. Prod has no order with more
-- than one allocation TODAY (max 1 of 130), which is today's data and not a
-- rule: partial payments are ordinary in an A/R ledger and the schema allows
-- them.
--
-- 🔴 WHY A SECOND MIGRATION AND NOT AN EDIT. `20261125000002` is applied to
-- staging. `db push` never re-applies an edited file, so editing it would leave
-- staging on the old text forever while prod got the new -- the divergence that
-- rule exists to prevent. This file is additive and idempotent instead.
--
-- Takes no lock on `orders`: replacing a trigger function keeps its oid, so the
-- triggers that reference it are untouched and are not re-created here.

begin;

-- ---------------------------------------------------------------------------
-- The function, copied verbatim from 20261125000002 with ONE key added.
-- 🔴 NEVER RETYPE A FUNCTION BODY: create or replace rewrites ALL of it, so a
-- body typed from memory silently drops whatever I failed to remember.
-- ---------------------------------------------------------------------------

create or replace function public.order_activity_money_row()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_event  text;
  v_detail jsonb;
  v_source text;
  v_member text;
  v_label  text;
  v_via    text;
begin
  -- An allocation or a transaction with no order is not an order's business.
  if new.order_id is null then
    return null;
  end if;

  if tg_table_name = 'invoice_payment_allocations' then
    v_event  := 'payment_allocated';
    -- 🔴 WHERE THE MONEY CAME FROM, BECAUSE THE ACTOR CANNOT SAY IT. The pay
    -- link inserts allocations with an ADMIN client (app/(shop)/[slug]/pay/
    -- actions-pay.ts), so there is no JWT and the actor below resolves to
    -- 'System' for a payment the CUSTOMER made. Measured on prod: 13 of the
    -- 112 payments have source 'online', and every one of them has
    -- `created_by` null -- there is no second signal. The payment's own
    -- `source` is the fact that tells them apart, so read it here and let the
    -- customer be named for their own payment.
    select p.source into v_source
      from public.invoice_payments p
     where p.payment_id = new.payment_id
       and p.company_id = new.company_id;
    v_detail := jsonb_build_object('amount_cents', new.amount_cents,
                                   'source', v_source,
                                   'allocation_id', new.allocation_id);
  else
    -- payment_transactions. A decline belongs in the log as much as a capture:
    -- "why does this order still owe" is the question the log is read for.
    v_event  := 'payment_attempted';
    v_detail := jsonb_build_object(
      'type', new.type, 'status', new.status,
      'amount_cents', new.gross_amount_cents,
      'response_text', nullif(new.response_text, ''));
  end if;

  select a.team_member_id, a.label, a.via into v_member, v_label, v_via
    from public.order_activity_actor() a limit 1;

  -- An online payment is the customer's doing whatever the connection looks
  -- like. Only when the actor came back anonymous: a staff member taking a
  -- card over the counter through the same screen is still that staff member.
  if v_source = 'online' and v_member is null then
    v_label := 'Customer, online';
    v_via   := 'customer';
  end if;

  insert into public.order_activity
    (company_id, order_id, event, actor_team_member_id, actor_label, actor_via, detail)
  values
    (new.company_id, new.order_id, v_event, v_member, v_label, v_via, v_detail);

  return null;
end;
$$;

comment on function public.order_activity_money_row() is
  'Logs a payment against an order. Separate from order_activity_row because payments do not move an orders column -- see 20261125000002. Carries the allocation id so the reader can tell WHICH payment the log already holds -- see 20261125000006.';

-- ---------------------------------------------------------------------------
-- Verify. The text search is weak in one direction -- a comment holding the
-- token would pass falsely -- so the token appears exactly once in this body,
-- in the code, in no comment, asserted when the file was written. The trigger
-- count is the assertion text cannot fake: replacing the function must leave
-- both money triggers pointing at it.
-- ---------------------------------------------------------------------------
do $verify$
declare
  v_src   text;
  v_trigs int;
begin
  select p.prosrc into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'order_activity_money_row';

  if v_src is null then
    raise exception 'order_activity_money_row() is missing';
  end if;

  if position('''allocation_id'', new.allocation_id' in v_src) = 0 then
    raise exception 'order_activity_money_row() does not record the allocation id';
  end if;

  select count(*) into v_trigs
    from pg_trigger t
   where not t.tgisinternal
     and t.tgfoid = 'public.order_activity_money_row()'::regprocedure;

  if v_trigs <> 2 then
    raise exception 'expected 2 money triggers on order_activity_money_row(), found %', v_trigs;
  end if;

  raise notice 'order_activity_money_row() records the allocation id; % triggers intact', v_trigs;
end
$verify$;

commit;
