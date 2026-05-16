-- Demo fixes: consumable stock, customer uniqueness, origin renames, product group renames,
-- recipe renames, 30 open orders, and refresh views
SET statement_timeout = 0;
SET session_replication_role = replica;

-- ============================================================
-- 1. FIX CONSUMABLE STOCK
--    Copy Social Hour's consumable_inventory_history + consumable_inventory_purchased
--    The original migration forgot these — without them the view baseline is 0 everywhere.
-- ============================================================

-- Rebuild consumable ID mapping (same ORDER BY as original migration → same dst IDs)
CREATE TEMP TABLE _fix_map_consumables AS
  SELECT consumable_inventory_id AS src,
    'demo-cons-' || row_number() OVER(ORDER BY consumable_inventory_id) AS dst
  FROM consumable_inventory
  WHERE facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de';

-- Rebuild shipment ID mapping (same ORDER BY as original migration → same dst IDs)
CREATE TEMP TABLE _fix_map_shipments AS
  SELECT shipment_id AS src,
    'demo-ship-' || row_number() OVER(ORDER BY shipment_id) AS dst
  FROM shipment_received
  WHERE facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de';

-- Copy consumable_inventory_history (remap consumable_id)
INSERT INTO consumable_inventory_history (
  history_id, consumable_id, inventory_date, inventory_count,
  notes, company_id, facility_id, created_at, updated_at)
SELECT
  gen_random_uuid()::text, mc.dst, cih.inventory_date, cih.inventory_count,
  cih.notes, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery',
  cih.created_at, cih.updated_at
FROM consumable_inventory_history cih
JOIN _fix_map_consumables mc ON mc.src = cih.consumable_id
WHERE cih.facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de';

-- Copy consumable_inventory_purchased
-- consumable_inventory_item stores the consumable_inventory_id (FK by value) — must remap it too
INSERT INTO consumable_inventory_purchased (
  consumable_purchase_id, shipment_id, consumable_inventory_item,
  cost_unit, amount, company_id, facility_id, created_at, updated_at)
SELECT
  gen_random_uuid()::text, ms.dst, mc.dst,
  cip.cost_unit, cip.amount, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery',
  cip.created_at, cip.updated_at
FROM consumable_inventory_purchased cip
JOIN _fix_map_shipments ms ON ms.src = cip.shipment_id
JOIN _fix_map_consumables mc ON mc.src = cip.consumable_inventory_item
WHERE cip.facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de';

-- ============================================================
-- 2. FIX CUSTOMER UNIQUENESS
--    Original DO block cycled same counter for first+last name → every name repeated ~7×.
--    New approach: first 140 customers get business names (unique), rest get individual
--    names using independent counters: first_name[i%100] + last_name[(i/100)%100]
--    → 100×100 = 10,000 unique combos, no repeats for 818 customers.
-- ============================================================
DO $$
DECLARE
  biz_names TEXT[] := ARRAY[
    'Threshold Coffee Co','Compass Coffee','Slate & Grind','Onyx Supply Co',
    'Verve Coffee Roasters','Toby''s Estate','Blue Bottle Café','Intelligentsia',
    'Stumptown Coffee Bar','La Colombe Café','Sightglass Coffee','Ritual Coffee',
    'Equator Coffees','Bird Rock Coffee','Coava Coffee','Heart Coffee',
    'Water Avenue Coffee','Roseline Coffee','Nossa Familia','Guilder Café',
    'Sterling Coffee','Good Coffee','Deadstock Coffee','Push X Pull Coffee',
    'Never Coffee','Either/Or','Proud Mary','Case Study Coffee',
    'Extracto Coffee','Coffee House Northwest','Courier Coffee','Cellar Door Coffee',
    'Olympia Coffee','Tony''s Coffee','Lighthouse Roasters','Broadcast Coffee',
    'Hothouse Coffee','Analog Coffee','Elm Coffee','Fulcrum Coffee',
    'Herkimer Coffee','Victrola Coffee','Caffe Vita','Espresso Vivace',
    'Zoka Coffee','Seattle Coffee Works','Capitol Hill Coffee','Anchorhead Coffee',
    'Ada''s Technical Books','Bedlam Coffee','Elm Street Coffee','Bar Del Corso',
    'Preserve & Gather','Communion','Gabi & Jules','Lighthouse Boulangerie',
    'Seven Coffee Roasters','Upper Left Roasters','Public Domain','Spella Caffè',
    'Barista PDX','Water Avenue Roasters','Cathedral Coffee','Fresh Pot Coffee',
    'Never Coffee Lab','Heart Espresso Bar','Quaintrelle','Ava Gene''s',
    'Roman Candle Baking','Little T Baker','Grand Central Bakery','Tabor Bread',
    'Ken''s Artisan Bakery','Nuvrei Patisserie','City State Coffee','Cerimon House',
    'Nostrana','Tasty n Daughters','Tusk Restaurant','Luce Restaurant',
    'Ox Restaurant','Canard Wine Bar','Han Oak','Imperial Hotel',
    'Headwaters Restaurant','Jackrabbit Portland','Mother''s Bistro','Pix Patisserie',
    'Pinolo Gelato','Pepe Le Moko','Clyde Common','The Rambler PDX',
    'Loyal Legion','Ecliptic Brewing','Stormbreaker Brewing','Breakside Brewery',
    'pFriem Family Brewers','Crux Fermentation','Boneyard Beer','Deschutes Brewery',
    'Ninkasi Brewing','Oakshire Brewing','Falling Sky Brewing','McMenamins',
    'Hop Valley Brewing','GoodLife Brewing','Terminal Gravity','Worthy Brewing',
    'Alpine Trail Roasters','Summit Coffee Supply','Ridge Coffee Co','Canyon Brew',
    'Ironwood Coffee','Backwood Roasters','Watershed Coffee','Common Thread Café',
    'Forward Motion Café','Morning Watch Coffee','Waypoint Coffee','Dusk Coffee Bar',
    'Deep Cut Coffee','Hearthstone Café','Ridgeline Coffee','Hillside Coffee',
    'Bedrock Coffee','True North Coffee','Harmony Coffee','French Quarter Coffee',
    'Evening Decaf Bar','Artisan Bakery & Coffee','Java Café Supply','Centerpoint Coffee',
    'Nightwatch Latte Bar','Familia Coffee','Analog Coffee Bar','Trotter''s Coffee',
    'Vida Coffee','Prism Coffee','Stellar Coffee Bar','Sol Café',
    'Crema Coffee Bar','Cold Brew Station','Electric Coffee','Backbeat Café'
  ];
  first_names TEXT[] := ARRAY[
    'James','John','Robert','Michael','William','David','Richard','Joseph','Thomas','Charles',
    'Christopher','Daniel','Matthew','Anthony','Mark','Donald','Steven','Paul','Andrew','Joshua',
    'Kenneth','Kevin','Brian','George','Timothy','Ronald','Edward','Jason','Jeffrey','Ryan',
    'Jacob','Gary','Nicholas','Eric','Jonathan','Stephen','Larry','Justin','Scott','Brandon',
    'Benjamin','Samuel','Raymond','Gregory','Frank','Alexander','Patrick','Jack','Dennis','Jerry',
    'Mary','Patricia','Jennifer','Linda','Barbara','Elizabeth','Susan','Jessica','Sarah','Karen',
    'Lisa','Nancy','Betty','Margaret','Sandra','Ashley','Dorothy','Kimberly','Emily','Donna',
    'Michelle','Carol','Amanda','Melissa','Deborah','Stephanie','Rebecca','Sharon','Laura','Cynthia',
    'Kathleen','Amy','Angela','Shirley','Anna','Brenda','Pamela','Emma','Nicole','Helen',
    'Samantha','Katherine','Christine','Debra','Rachel','Carolyn','Janet','Catherine','Maria','Heather'
  ];
  last_names TEXT[] := ARRAY[
    'Smith','Johnson','Williams','Brown','Jones','Garcia','Miller','Davis','Wilson','Anderson',
    'Taylor','Thomas','Hernandez','Moore','Martin','Jackson','Thompson','White','Lopez','Lee',
    'Gonzalez','Harris','Clark','Lewis','Robinson','Walker','Perez','Hall','Young','Allen',
    'Sanchez','Wright','King','Scott','Green','Baker','Adams','Nelson','Hill','Ramirez',
    'Campbell','Mitchell','Roberts','Carter','Phillips','Evans','Turner','Torres','Parker','Collins',
    'Edwards','Stewart','Flores','Morris','Nguyen','Murphy','Rivera','Cook','Rogers','Morgan',
    'Peterson','Cooper','Reed','Bailey','Bell','Gomez','Kelly','Howard','Ward','Cox',
    'Diaz','Richardson','Wood','Watson','Brooks','Bennett','Gray','James','Reyes','Cruz',
    'Hughes','Price','Myers','Long','Foster','Sanders','Ross','Morales','Powell','Sullivan',
    'Russell','Ortiz','Jenkins','Gutierrez','Perry','Butler','Barnes','Fisher','Henderson','Coleman'
  ];
  rec RECORD;
  rn INT := 0;
BEGIN
  FOR rec IN
    SELECT customer_id FROM customers
    WHERE facility_id = 'demo-kailua-roastery'
    ORDER BY customer_id
  LOOP
    IF rn < 140 THEN
      UPDATE customers SET name_company = biz_names[rn + 1]
      WHERE customer_id = rec.customer_id;
    ELSE
      UPDATE customers SET name_company =
        first_names[((rn - 140) % 100) + 1] || ' ' ||
        last_names[((rn - 140) / 100 % 100) + 1]
      WHERE customer_id = rec.customer_id;
    END IF;
    rn := rn + 1;
  END LOOP;
END $$;

-- ============================================================
-- 3. RENAME HAWAII COFFEE ORIGINS
--    Keep: Kona Extra Fancy, Maui Mokka (user: "leave a couple Hawaii coffees")
--    Rename: everything else Hawaii-specific
-- ============================================================
UPDATE coffee_inventory SET origin = CASE origin
  WHEN 'Kona SL34'        THEN 'Kenya SL34'
  WHEN 'Mahi Pono Yellow' THEN 'Colombia Yellow Honey'
  WHEN 'Maui Red'         THEN 'Ethiopia Natural'
  WHEN 'Maui Yellow'      THEN 'Costa Rica Yellow Honey'
  WHEN 'Mokka Peaberry'   THEN 'Yemen Peaberry'
  WHEN 'Golden Hour'      THEN 'Pacific Blend'
  WHEN 'Chocolate'        THEN 'Low Acidity'
  WHEN 'Fruit'            THEN 'High Acidity'
  ELSE origin
END WHERE facility_id = 'demo-kailua-roastery';

-- Update roast_log.coffee_name_snapshot for renamed origins
UPDATE roast_log SET coffee_name_snapshot = CASE coffee_name_snapshot
  WHEN 'Kona SL34'        THEN 'Kenya SL34'
  WHEN 'Mahi Pono Yellow' THEN 'Colombia Yellow Honey'
  WHEN 'Maui Red'         THEN 'Ethiopia Natural'
  WHEN 'Maui Yellow'      THEN 'Costa Rica Yellow Honey'
  WHEN 'Mokka Peaberry'   THEN 'Yemen Peaberry'
  WHEN 'Golden Hour'      THEN 'Pacific Blend'
  WHEN 'Chocolate'        THEN 'Low Acidity'
  WHEN 'Fruit'            THEN 'High Acidity'
  ELSE coffee_name_snapshot
END WHERE facility_id = 'demo-kailua-roastery';

-- ============================================================
-- 4. RENAME REMAINING RECOGNIZABLE PRODUCT GROUPS
--    (Vinyl, Nova, Rubix, Sol Do Brasil, Vigilatte, Vida Roast, Hendrix, Fruit)
-- ============================================================
UPDATE product_groups SET group_name = CASE group_name
  WHEN 'Fruit'         THEN 'High Acidity'
  WHEN 'Vinyl'         THEN 'Analog'
  WHEN 'Nova'          THEN 'Stellar'
  WHEN 'Rubix'         THEN 'Prism'
  WHEN 'Sol Do Brasil' THEN 'Sol Brazil'
  WHEN 'Vigilatte'     THEN 'Nightwatch Latte'
  WHEN 'Vida Roast'    THEN 'Vida'
  WHEN 'Hendrix'       THEN 'Electric'
  WHEN 'Cold Brew'     THEN 'Cold Brew Blend'
  WHEN 'Crema Blend'   THEN 'Cream Line'
  ELSE group_name
END WHERE company_id = 'demo-aloha-coffee-roasters';

-- ============================================================
-- 5. RENAME RECIPES to match renamed groups/origins
-- ============================================================
UPDATE roast_recipes SET recipe_name = CASE recipe_name
  WHEN 'Fruit'               THEN 'High Acidity Blend'
  WHEN 'Nova'                THEN 'Stellar'
  WHEN 'Nova Brazil'         THEN 'Stellar Brazil'
  WHEN 'Nova Brazil Reserve' THEN 'Stellar Brazil Reserve'
  WHEN 'Nova Reserve'        THEN 'Stellar Reserve'
  WHEN 'Rubix'               THEN 'Prism'
  WHEN 'Sol Do Brasil'       THEN 'Sol Brazil'
  WHEN 'Vinyl'               THEN 'Analog'
  WHEN 'Hendrix'             THEN 'Electric'
  WHEN 'Hendrix Reserve'     THEN 'Electric Reserve'
  ELSE recipe_name
END WHERE facility_id = 'demo-kailua-roastery';

-- Update recipe_name_snapshot in roast_log for renamed recipes
UPDATE roast_log SET recipe_name_snapshot = CASE recipe_name_snapshot
  WHEN 'Fruit'               THEN 'High Acidity Blend'
  WHEN 'Nova'                THEN 'Stellar'
  WHEN 'Nova Brazil'         THEN 'Stellar Brazil'
  WHEN 'Nova Brazil Reserve' THEN 'Stellar Brazil Reserve'
  WHEN 'Nova Reserve'        THEN 'Stellar Reserve'
  WHEN 'Rubix'               THEN 'Prism'
  WHEN 'Sol Do Brasil'       THEN 'Sol Brazil'
  WHEN 'Vinyl'               THEN 'Analog'
  WHEN 'Hendrix'             THEN 'Electric'
  WHEN 'Hendrix Reserve'     THEN 'Electric Reserve'
  ELSE recipe_name_snapshot
END WHERE facility_id = 'demo-kailua-roastery';

-- ============================================================
-- 6. MARK 30 MOST RECENT DELIVERED ORDERS AS OPEN
-- ============================================================
-- Update order_details first (FK child)
UPDATE order_details SET item_status = 'Open'
WHERE facility_id = 'demo-kailua-roastery'
  AND order_id IN (
    SELECT order_id FROM orders
    WHERE facility_id = 'demo-kailua-roastery' AND order_status = 'Delivered'
    ORDER BY order_date DESC, order_id DESC
    LIMIT 30
  );

-- Update orders
UPDATE orders SET order_status = 'Open'
WHERE facility_id = 'demo-kailua-roastery' AND order_status = 'Delivered'
  AND order_id IN (
    SELECT order_id FROM orders
    WHERE facility_id = 'demo-kailua-roastery' AND order_status = 'Delivered'
    ORDER BY order_date DESC, order_id DESC
    LIMIT 30
  );

-- ============================================================
-- 7. RE-FIRE PRODUCT NAME TRIGGER for renamed groups
-- ============================================================
SET session_replication_role = DEFAULT;
UPDATE products SET group_id = group_id WHERE facility_id = 'demo-kailua-roastery';

-- ============================================================
-- 8. REFRESH MATERIALIZED VIEWS
-- ============================================================
REFRESH MATERIALIZED VIEW monthly_consumable_stock_by_item;
REFRESH MATERIALIZED VIEW weekly_coffee_stock_by_origin;
REFRESH MATERIALIZED VIEW order_graphs_week;
