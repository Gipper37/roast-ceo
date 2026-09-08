-- 2026-08-31 · MCR: line totals that hold ONE bag's price for a multi-bag qty.
--
-- Operators typed the per-bag price into the order form's line money field,
-- which is the line TOTAL — so qty 5 of a $74.75 bag billed $74.75. Ten lines
-- across six Open, un-posted, un-invoiced orders (owner confirmed the intent:
-- the typed number is the bag price). Fix: unit_price_at_sale = the typed bag
-- price, total_price = qty × bag price; orders.order_total follows via
-- trg_update_order_totals_upd.
--
-- Guarded per row on the CURRENT broken total, so a re-run (or a line someone
-- already corrected by hand) matches nothing. Snapshot of the before-state:
-- scripts/mcr_line_total_qty_snapshot_2026-08-31.tsv

begin;

update order_details od
set unit_price_at_sale = v.bag_price,
    total_price = round(od.quantity * v.bag_price, 2)
from (values
  ('5092da6a-b5ac-4bc5-8e0a-74fcce5cdc27', 74.75::numeric),  -- Freshies · Org Dark 5lb ×5
  ('e5aa18a7-2784-4575-9501-811c3e5e8e27', 74.75),           -- Grandma's · Org French 5lb ×6
  ('d90d63e3-f8eb-4e19-976e-9908ced9ba80', 12.13),           -- Kraken · Decaf 1lb ×5
  ('3ec5520e-7e64-42b3-ae20-78b9d51b9856', 6.18),            -- Kraken · Maui Blend 8oz ×20
  ('1071f30d-5d1e-4569-b6d6-3dc6112f003f', 12.35),           -- Kraken · Maui Blend 1lb ×10
  ('4d57fe2e-7360-4965-babf-bbd033853c94', 61.75),           -- Kraken · Maui Blend 5lb ×16
  ('a8c9f322-2e70-49dd-a64d-35eb37ac468c', 133.75),          -- Mamas · Red Moka 5lb ×2
  ('2cb5fdcf-b039-4b11-9769-8a5381c9a7a2', 74.75),           -- Mana · Org Dark 5lb ×3
  ('1ae79bc7-32ef-4c39-858b-12acfa8cbe27', 74.75),           -- Mana · Org French 5lb ×3
  ('b9739acb-e010-429e-8057-babd2ba5342e', 14.15)            -- Nahiku · Red Bag 8oz ×15
) as v(order_detail_id, bag_price)
where od.order_detail_id::text = v.order_detail_id
  and od.total_price = v.bag_price;

-- What the six orders look like after the update (inside the txn).
select c.name_company, o.order_id, o.order_total
from orders o left join customers c on c.customer_id = o.customer_id
where o.order_id in (
  'ea115468-94c5-4238-98f8-f28229b5246c',  -- expect  373.75 (was   74.75)
  '4e3de9d1-719d-412d-92b2-b5f2f35cf9d8',  -- expect  523.25 (was  149.50)
  '75809eed-4b39-4f27-a484-795eb12af28e',  -- expect 1295.75 (was   92.41)
  '375fa9d8-5ee8-4c42-afa7-6978dc37ae2b',  -- expect 1238.36 (was 1104.61)
  '23355f64-7cab-461a-92c4-75b4a18aa275',  -- expect  672.75 (was  373.75)
  'eb6f7eb6-d32d-4b99-ba43-f753a909d198'   -- expect 1076.15 (was  878.05)
)
order by c.name_company;

commit;
