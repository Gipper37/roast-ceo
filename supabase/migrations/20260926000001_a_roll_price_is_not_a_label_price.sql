-- A roll of labels is not a label.
--
-- The Products page reported 85.9% average COGS. The coffee was never the
-- problem: 31 labels carry the price of the ROLL in per-label fields, so every
-- product using one carries a whole roll in its cost. Club Imua 8oz sells for
-- $6.24 and reported a COGS of $125.51, of which $122.50 was one label.
--
-- WHY THIS IS A UNIT MIX-UP AND NOT A PRICE RANGE:
--   * Labels split in two with nothing between them — 12 priced
--     $0.0618-$0.2857, and 31 priced $60.00-$417.00.
--   * 11 of the 12 correct ones got their price from a RECEIVED PURCHASE.
--     NOT ONE of the 31 has a purchase record — the roll price was typed
--     straight into the unit-cost cell.
--   * $122.50 / 1000 = $0.1225, inside the band the correct labels occupy.
--     So are $60, $61.48, $70, $85, $110 and $199.38.
--
-- Owner, this session: labels come in rolls of 1000; correct all of them,
-- including the fallback.
--
-- SELECTED BY CAUSE, NOT MAGNITUDE: "a label priced like a roll that nobody
-- ever received". 32 labels have no purchase record and one of those is
-- correctly priced at pennies, so price alone would have caught it too. Both
-- conditions together select exactly 31, and only at MCR — no other tenant has
-- a single roll-priced label.
--
-- BOTH COLUMNS. last_cost_unit is what update_product_total_cogs reads, and
-- fallback_unit_cost is what get_consumable_cost_on_date falls back to when an
-- item has no purchase — which is true of all 31. Fixing only the first would
-- leave the roll price reaching the books through get_product_cogs_on_date.
--
-- 🔴 This is the column pair that caused a live incident on 2026-09-08, when
-- 20260908000011 substituted fallback INTO last_cost_unit and pushed products
-- from 47% to 92% COGS. That was a derived cache inventing a number with no
-- owner behind it. This is the opposite: an explicit owner instruction, applied
-- to both columns so they agree, with the before-state recorded below so it can
-- be undone by multiplying these rows by 1000 again.
--
-- 'Made in Maui 3.5"' at $417 becomes $0.417, above the $0.2857 the other
-- labels top out at. It is used by ZERO products so it cannot affect any COGS;
-- corrected for consistency and named here rather than quietly rounded.
--
-- BEFORE (both columns held this value):
--   cons_814ba5e8d471105e          100% Maui Back Label                   199.38
--   cons_65db84c6160a7b86          16oz Castaway Coffee Label              122.5
--   cons_e6d634eb2983cb66          16oz Maui Cat Label                     122.5
--   cons_556c0b02d49f5a15          16oz Maui Moka Label                    122.5
--   cons_c9e7139e54e5946c          16oz Red Rooster Label                  122.5
--   cons_8ff822b7c88c8910          2lb Costco Hula Label                   110.0
--   cons_e4ec65a03ccfcbb8          2oz Maui Blend Label                     85.0
--   cons_53e35ea34eb75e21          2oz Maui Blend Label                     85.0
--   cons_0d9fd924fc7a144c          4x1.5 Glossy                             60.0
--   cons_489837bc428565ba          4x3 Glossy                               60.0
--   cons_62cf1b3660ddbf8e          4x3 Matt                                 60.0
--   cons_9f4548aa601bf505          8oz Castaway Label                      122.5
--   cons_105a9a10c0167f47          8oz Club Imua Label                     122.5
--   cons_766b4f6de2b8d4a2          8oz Hawaii Label Back - WFM             122.5
--   cons_51f61e3816c172a1          8oz Hawaii Label Front - WFM            122.5
--   cons_3b7f89a10b1af086          8oz Ka'u Label Back - WFM               122.5
--   cons_67a9d7f84615337c          8oz Ka'u Label Front - WFM              122.5
--   cons_b201a606ad01b5bd          8oz Kona Label Back - WFM               122.5
--   cons_7076e24a013366d9          8oz Kona Label Front - WFM              122.5
--   cons_7d96fceeb42529c6          8oz Maui Cat Label                      122.5
--   cons_72b04dde0e184af5          8oz Maui Moka Label                     122.5
--   cons_369476ec3a92c615          8oz Nicky Beans Kona Label - Gold        85.0
--   cons_d522a3a3ca490f76          8oz Nicky Beans Kona Label - Gold        85.0
--   cons_14d7ae711b1b37d5          8oz Nicky Beans Kona Label - Silver      85.0
--   cons_483e7d2d60141b5e          8oz Red Rooster Label                   122.5
--   cons_e6d6d49918998799          Custom 2.75 x 1.75                      61.48
--   cons_3c00a4346eeab1b2          Fresh Trades Label                      122.5
--   cons_c45d5be2e1d9e067          Ka'u Label                              122.5
--   cons_ef583688ec2eed99          Made in Maui 3.5"                       417.0
--   cons_19be15adcbfd055b          Marriot                                 122.5
--   cons_ee9900f4abcb69f6          Oval Decaf                               70.0
--
-- Product COGS recomputes itself: trg_propagate_consumable_cost fires AFTER
-- UPDATE OF last_cost_unit.

begin;

create temporary table _label_fix on commit drop as
  select ci.consumable_inventory_id  as id,
         ci.last_cost_unit           as roll_price
    from public.consumable_inventory ci
    join public.consumable_type ct on ct.consumable_type_id = ci.consumable_type
   where ct.consumable_type = 'Label (BOM)'
     and ci.last_cost_unit >= 50
     and not exists (select 1 from public.consumable_inventory_purchased cip
                      where cip.consumable_inventory_item = ci.consumable_inventory_id);

-- fallback first: its own triggers derive from it, so settling it before
-- last_cost_unit means the final propagation runs on the corrected pair.
update public.consumable_inventory ci
   set fallback_unit_cost = f.roll_price / 1000.0
  from _label_fix f
 where ci.consumable_inventory_id = f.id;

update public.consumable_inventory ci
   set last_cost_unit = f.roll_price / 1000.0
  from _label_fix f
 where ci.consumable_inventory_id = f.id;

do $verify$
declare v_fixed int; v_left int; v_bad int; v_avg numeric; v_med numeric; v_over int;
begin
  select count(*) into v_fixed from _label_fix;
  if v_fixed = 0 then raise exception 'nothing matched — the selector no longer describes the defect'; end if;

  -- Scoped to labels with NO purchase record, because those are the only ones
  -- where either column can reach a cost calculation unchallenged.
  --
  -- 9 OTHER labels keep a roll price in fallback_unit_cost — 8oz Hula Label
  -- Black is $0.18 with a $85.00 fallback — and they are deliberately left
  -- alone. Each has real purchases, so last_cost_unit is authoritative and
  -- get_consumable_cost_on_date never reaches their fallback. Their implied
  -- roll sizes are 429 to 1214, NOT 1000, so dividing them by 1000 would turn
  -- a genuine $0.18 label into $0.075. Two of them sit in 57 and 74 bills of
  -- materials; guessing there would be expensive.
  select count(*) into v_left
    from public.consumable_inventory ci
    join public.consumable_type ct on ct.consumable_type_id = ci.consumable_type
   where ct.consumable_type = 'Label (BOM)'
     and not exists (select 1 from public.consumable_inventory_purchased cip
                      where cip.consumable_inventory_item = ci.consumable_inventory_id)
     and (ci.last_cost_unit >= 50 or ci.fallback_unit_cost >= 50);
  if v_left > 0 then raise exception '% unpurchased label(s) still priced like a roll', v_left; end if;

  -- The two columns must agree, or the books and the product card disagree.
  select count(*) into v_bad
    from public.consumable_inventory ci join _label_fix f on f.id = ci.consumable_inventory_id
   where ci.last_cost_unit is distinct from ci.fallback_unit_cost;
  if v_bad > 0 then raise exception '% row(s) left the two cost columns disagreeing', v_bad; end if;

  -- Scoped to what this migration is responsible for: a product that uses one
  -- of the labels I just repriced must no longer be carrying a roll.
  --
  -- Deliberately NOT "no product over 100% COGS". That is true on prod and
  -- false on the demo seed, and it is not an invariant anyway: a sample or a
  -- loss-leader can honestly cost more than it sells for. Guittard Caramel
  -- Sauce (106.8%) and Cafiza 566g Jar (100.3%) are resold items with no BOM
  -- at all, sold at cost — a pricing fact, not a data error. Asserting one
  -- environment's rows is the mistake that has bitten this repo four times in
  -- a week.
  select count(*) into v_over
    from public.products p
   where p.is_active and p.cogs_pct > 100
     and exists (select 1 from public.product_consumables pc
                  join _label_fix f on f.id = pc.consumable_id
                 where pc.product_id = p.product_id);
  if v_over > 0 then
    raise exception '% product(s) using a repriced label are still over 100%% COGS', v_over;
  end if;

  select round(avg(cogs_pct),1), round(percentile_cont(0.5) within group (order by cogs_pct)::numeric,1)
    into v_avg, v_med
    from public.products where is_active and cogs_pct is not null;
  raise notice '% labels repriced from roll to label; average COGS now %%%, median %%%', v_fixed, v_avg, v_med;
end $verify$;

commit;
