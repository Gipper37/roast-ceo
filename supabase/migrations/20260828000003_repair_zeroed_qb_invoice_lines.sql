-- Repair 37 QuickBooks invoices whose lines were zeroed on import.
--
-- 39 MCR orders had order_total disagreeing with the sum of their own lines, by
-- $20,393.86 gross. Invoices read order_total; every revenue view reads the
-- lines. So those orders disagreed with themselves depending on who asked.
--
-- CAUSE, traced end to end. They are mcrimp-ord-* QuickBooks imports that never
-- got is_legacy_import set. Without that flag handle_order_detail_logic
-- recomputed each line from products.price — and these products carry no
-- catalogue price — so every line became $0.00 while order_total kept the
-- figure the importer had written from QuickBooks. Example:
--
--   Mamas Fish House, 2025-06-01, QB invoice "cs special"
--   QB line: Invoice Sale, qty 1, $11,038.40
--   STRATA:  Invoice Sale, qty 1, total_price $0.00
--
-- It never self-heals: the lines are stuck at zero, so total_price never
-- CHANGES, so the conditional aggregate trigger never fires again.
--
-- VERIFIED AGAINST THE SOURCE, not inferred. Every order was matched to its
-- QuickBooks document by customer and date and reconciled LINE BY LINE against
-- the original invoice — 90 lines across 37 orders, restoring $12,839.65.
--
-- Matching had to compare against QuickBooks' SUBTOTAL, not its `total`: the
-- QB total is tax-INCLUSIVE. My first pass compared the wrong two numbers and
-- reported 24 orders as irreconcilable when the gap was simply the 0.5% General
-- Excise Tax (477.43/476.00, 130.65/130.00, 325.42/323.80 — all 1.005).
--
-- HOW: amount_override is exactly the mechanism for "this line was invoiced at
-- this amount", and the trigger honours it verbatim, so total_price follows and
-- update_order_aggregates re-sums order_total. THEN is_legacy_import is set —
-- second, because setting it first would make the trigger skip and leave every
-- line at zero forever. With it set, no future price change can restate these
-- invoices, which is the whole reason the other 3,759 imported orders carry it.
--
-- Ten of the 90 lines are Sales Discount and every one is already negative, so
-- 20260828000001's sign rule changes none of them. Checked, not assumed.
--
-- NOT REPAIRED — 2 orders left for the owner, because they need a judgement
-- rather than a lookup. Cinnamon Roll Place 2026-02-18 and My Titas Cafe
-- 2026-02-19 have order_total $0.00 but lines carrying $26.15 and $82.03, and
-- their QuickBooks counterparts are QUOTES (#QUOTE103313, #QUOTE21926) worth
-- nothing. Whether those were real sales is not something this migration can
-- decide.
--
-- Rehearsed on prod inside a rolled-back transaction:
--   37 of 37 orders reconcile order_total to their lines
--   $12,839.65 restored across 90 lines
--   10 discount lines still negative, -$3,006.56
--   MCR drift 39 -> 2
--   0 orders outside the repair set touched

begin;

create temporary table qb_repair(order_detail_id text primary key, qb_amount numeric) on commit drop;
insert into qb_repair(order_detail_id, qb_amount) values
    ('mcrimp-od-d9025f7d6eb9e700', 11038.40),
    ('mcrimp-od-54e4f49e618d1929', 135.22),
    ('mcrimp-od-5bbdd4b46a6e2ae0', 0.00),
    ('mcrimp-od-b99e2c1e77600a56', -137.69),
    ('mcrimp-od-764e34e769c7c1c3', 25.00),
    ('mcrimp-od-418f24214958a50c', 109.80),
    ('mcrimp-od-a38a536f8fc107b5', 214.00),
    ('mcrimp-od-6f94246bf86bc50e', 130.00),
    ('mcrimp-od-0e02f21fe49bbf5f', 26.00),
    ('mcrimp-od-10dde4cfae47232a', 190.00),
    ('mcrimp-od-8880ce8d5d443a9b', 260.00),
    ('mcrimp-od-461323f649c3bf38', 194.00),
    ('mcrimp-od-677e626a882996eb', 5.00),
    ('mcrimp-od-e51c8fe680d01352', 95.00),
    ('mcrimp-od-32050322e61fd138', 18.00),
    ('mcrimp-od-657972f856dee75b', 156.00),
    ('mcrimp-od-7bc9091818037c21', 2.60),
    ('mcrimp-od-8e6b28d70578fcb9', 95.00),
    ('mcrimp-od-f2fd97f97e949526', 10.00),
    ('mcrimp-od-32405f0721b90af7', 104.00),
    ('mcrimp-od-73f5a3a26e5c0546', 112.00),
    ('mcrimp-od-b5fd37f697e09072', 270.00),
    ('mcrimp-od-d50c19fa02a2d364', -200.11),
    ('mcrimp-od-bf2ae0482443faf2', 80.00),
    ('mcrimp-od-4a92a1034cb9253f', 10.00),
    ('mcrimp-od-e6d847a98b73a784', 14.95),
    ('mcrimp-od-07d3b40536eeb09b', -141.50),
    ('mcrimp-od-28fa5ba83ffd83d6', -43.25),
    ('mcrimp-od-4c63787ca24639e0', -23.50),
    ('mcrimp-od-9de00d8f70ebadef', -23.50),
    ('mcrimp-od-02d4a31fb4bba844', 26.00),
    ('mcrimp-od-51dc26ebd08e2b47', 30.00),
    ('mcrimp-od-b510ca780eaac72f', 95.00),
    ('mcrimp-od-1cf11cc4b32a8893', 26.00),
    ('mcrimp-od-2953468871d5167d', 30.00),
    ('mcrimp-od-88926bc0198195a1', 95.00),
    ('mcrimp-od-465e921d87d2afe5', 95.00),
    ('mcrimp-od-8eb65365e23dfced', 142.50),
    ('mcrimp-od-99f9bff621116f77', 12.00),
    ('mcrimp-od-a3d76fbbd17f3c74', 170.00),
    ('mcrimp-od-f1e3d9a876ed3a80', 150.00),
    ('mcrimp-od-105325c69f4d38a6', 40.00),
    ('mcrimp-od-8cb64475e5be87cf', 32.75),
    ('mcrimp-od-0a71f0df2a8600f4', 251.00),
    ('mcrimp-od-6c180d54d5852ceb', 97.85),
    ('mcrimp-od-7ce7be39c99737fc', 380.00),
    ('mcrimp-od-8a8829d8e7e53d84', 130.40),
    ('mcrimp-od-c7c6ef40b8a8df41', 115.18),
    ('mcrimp-od-e87000581ae65d83', -380.00),
    ('mcrimp-od-5ccecc9da1171981', -258.25),
    ('mcrimp-od-23293940293b430e', -59.04),
    ('mcrimp-od-06d9d5e14d0fe371', 125.00),
    ('mcrimp-od-308493346206d9fd', 50.00),
    ('mcrimp-od-7182580a266e4499', 77.74),
    ('mcrimp-od-cf137db84d3d9a9e', 450.00),
    ('mcrimp-od-26b6a3d68712f71c', 13.30),
    ('mcrimp-od-2ef13d50b303bbc5', 52.17),
    ('mcrimp-od-4c81e749c4bbbe26', 10.73),
    ('mcrimp-od-6d69aa72a9e78ac6', 95.00),
    ('mcrimp-od-6e55ed51eecf9d3f', 2.95),
    ('mcrimp-od-8737c4316eeaff37', 153.50),
    ('mcrimp-od-9ee0370f4b9ff3b5', 24.63),
    ('mcrimp-od-cd8af15ff54b66d6', 82.31),
    ('mcrimp-od-f42e4feb7a3b153b', 1.00),
    ('mcrimp-od-1c7ec60c97153b10', 101.20),
    ('mcrimp-od-ab0e1ad12b096631', 47.50),
    ('mcrimp-od-0d1807bfce454761', -1004.40),
    ('mcrimp-od-34925fd27656aef9', -19.93),
    ('mcrimp-od-37bdabb0cfd98787', -338.28),
    ('mcrimp-od-3ccc3e8e6d4658c9', -747.87),
    ('mcrimp-od-3f7a7c0742715b89', -61.10),
    ('mcrimp-od-4171ee83b4cdac3e', -131.05),
    ('mcrimp-od-70a191654f91f1da', -595.46),
    ('mcrimp-od-8fbf8bb7ec228749', -205.50),
    ('mcrimp-od-f9d61776a633e03c', -389.68),
    ('mcrimp-od-14b9ea1c686f4243', 4.38),
    ('mcrimp-od-4c60a37e4c01246e', 4.38),
    ('mcrimp-od-65623ddb2c740ab4', 16.98),
    ('mcrimp-od-67bda20a65096794', 190.00),
    ('mcrimp-od-724a31389df09ce8', 85.65),
    ('mcrimp-od-a0ddead33e36ef0c', 3.44),
    ('mcrimp-od-b6b0fb996e0a2582', 81.50),
    ('mcrimp-od-b95e108715c9bf8e', 85.65),
    ('mcrimp-od-bb0df390a0044fb6', 125.00),
    ('mcrimp-od-f98c13d0f2c21c45', 81.00),
    ('mcrimp-od-03d8b548e445f727', 220.71),
    ('mcrimp-od-4cdf7118165c5d54', 12.48),
    ('mcrimp-od-974a44080197679e', 95.00),
    ('mcrimp-od-aa2bce694e00a4b4', 6.63),
    ('mcrimp-od-e3cf4be3b480dfe5', 86.28);

create temporary table qb_repair_orders(order_id text primary key) on commit drop;
insert into qb_repair_orders(order_id) values
    ('mcrimp-ord-6e9e4b5b9beab048'),
    ('mcrimp-ord-9eb571b29587350b'),
    ('mcrimp-ord-b4f50aa160c83369'),
    ('mcrimp-ord-30caa1abe4038aa1'),
    ('mcrimp-ord-37e6a7ae417ee26e'),
    ('mcrimp-ord-e31e83900de3e4ae'),
    ('mcrimp-ord-563ae2a1d5d30d8a'),
    ('mcrimp-ord-467748a0451c37cf'),
    ('mcrimp-ord-86dd43b654188c85'),
    ('mcrimp-ord-430f674318d884b3'),
    ('mcrimp-ord-0465f9cc268d8fa7'),
    ('mcrimp-ord-1d089f694d6d5ff9'),
    ('mcrimp-ord-f7ce6ccfc483f311'),
    ('mcrimp-ord-bfd4bb3b61560221'),
    ('mcrimp-ord-3b6f2f21d0665df1'),
    ('mcrimp-ord-f290e175b58032bc'),
    ('mcrimp-ord-f58b22bd21ef2373'),
    ('mcrimp-ord-d1f0d9c28b85313a'),
    ('mcrimp-ord-09cfa3ed6f31c3fb'),
    ('mcrimp-ord-cdb8615afd4fc3ca'),
    ('mcrimp-ord-82bd65614aa7e728'),
    ('mcrimp-ord-08ba5c6cba9a807e'),
    ('mcrimp-ord-b1072ac8e53fda23'),
    ('mcrimp-ord-dfdf0056ce14cc59'),
    ('mcrimp-ord-8810ae2cbd5c0bd6'),
    ('mcrimp-ord-54340798e1776f31'),
    ('mcrimp-ord-de30534ef7a3d1e8'),
    ('mcrimp-ord-d72f395738073f01'),
    ('mcrimp-ord-fed6616baec2947a'),
    ('mcrimp-ord-4fb15765a0cea37d'),
    ('mcrimp-ord-478517661f24f84f'),
    ('mcrimp-ord-ced966fdfc3e4341'),
    ('mcrimp-ord-a66291d2f18b7e63'),
    ('mcrimp-ord-1b19945df9d2c446'),
    ('mcrimp-ord-c66f561899630d1f'),
    ('mcrimp-ord-81fdb81e756816b4'),
    ('mcrimp-ord-3a735c00fe7e5f04');

-- 1. Restore each line to the amount QuickBooks invoiced. amount_override is
--    exactly the mechanism for this and the trigger honours it verbatim, so
--    total_price follows and update_order_aggregates re-sums order_total.
update public.order_details od
   set amount_override = q.qb_amount
  from qb_repair q
 where od.order_detail_id = q.order_detail_id;

-- 2. THEN mark them as the QuickBooks imports they always were. This has to come
--    second: is_legacy_import makes handle_order_detail_logic skip the recompute,
--    so setting it first would leave every line at zero forever. With it set, a
--    future price change can never restate these invoices — which is the whole
--    reason the other 3,759 imported orders carry it.
update public.orders o
   set is_legacy_import = true
  from qb_repair_orders r
 where o.order_id = r.order_id;
commit;
