-- Fix customer name distribution: use customer_category to drive business vs individual naming
-- Online → individual person names (470)
-- Cafe/Restaurant/Hospitality/Grocery/Non Traditional/VIP/NULL → business names (348)
SET statement_timeout = 0;
SET session_replication_role = replica;

DO $$
DECLARE
  -- 400 business names covering cafes, restaurants, hotels, groceries, misc
  biz_names TEXT[] := ARRAY[
    -- Cafes & Coffee
    'Threshold Coffee Co','Compass Coffee','Slate & Grind','Onyx Supply Co',
    'Verve Coffee Roasters','Toby''s Estate','Blue Bottle Café','Intelligentsia PDX',
    'Stumptown Coffee Bar','La Colombe Café','Sightglass Coffee','Ritual Coffee Roasters',
    'Equator Coffees','Bird Rock Coffee','Coava Coffee','Heart Coffee Roasters',
    'Water Avenue Coffee','Roseline Coffee','Nossa Familia Coffee','Guilder Café',
    'Sterling Coffee','Good Coffee Portland','Deadstock Coffee','Push X Pull Coffee',
    'Never Coffee','Either/Or PDX','Proud Mary','Case Study Coffee',
    'Extracto Coffee','Coffee House Northwest','Courier Coffee','Cellar Door Coffee',
    'Olympia Coffee','Tony''s Coffee','Lighthouse Roasters','Broadcast Coffee',
    'Hothouse Coffee','Analog Coffee','Elm Coffee Roasters','Fulcrum Coffee',
    'Herkimer Coffee','Victrola Coffee','Caffe Vita','Espresso Vivace',
    'Zoka Coffee','Seattle Coffee Works','Anchorhead Coffee','Bedlam Coffee',
    'Seven Coffee Roasters','Upper Left Roasters','Public Domain Coffee','Spella Caffè',
    'Barista PDX','Cathedral Coffee','Fresh Pot Coffee','Never Coffee Lab',
    'Heart Espresso Bar','City State Coffee','Sterling Grounds','Summit Coffee',
    'Ridge Coffee Co','Canyon Brew Coffee','Ironwood Coffee','Backwood Roasters',
    'Watershed Coffee','Common Thread Café','Forward Motion Café','Morning Watch Coffee',
    'Waypoint Coffee','Dusk Coffee Bar','Deep Cut Coffee','Hearthstone Café',
    'Ridgeline Coffee','Hillside Coffee','Bedrock Coffee','True North Coffee',
    'Harmony Coffee','French Quarter Coffee','Evening Decaf Bar','Nightwatch Café',
    'Analog Coffee Bar','Trotter''s Coffee','Vida Coffee','Prism Coffee',
    'Stellar Coffee Bar','Sol Café','Crema Coffee Bar','Electric Coffee Bar',
    'Backbeat Café','Alpine Trail Coffee','Eastside Coffee House','Uptown Coffee',
    'Highline Coffee','Westside Brew','Market Street Coffee','Pacific Coffee Works',
    'Harbor Coffee Co','Bayview Café','Cliffside Coffee','Ridgetop Roasters',
    'Irongate Coffee','Landmark Coffee','Flagstone Coffee','Crossroads Coffee',
    -- Restaurants & Bistros
    'Nostrana Restaurant','Tasty n Daughters','Tusk Restaurant','Luce Restaurant',
    'Ox Restaurant','Canard Wine Bar','Han Oak','Imperial Restaurant',
    'Headwaters Restaurant','Jackrabbit Portland','Mother''s Bistro','Quaintrelle',
    'Ava Gene''s','Roman Candle Baking Co','The Rambler PDX','Clyde Common',
    'Pepe Le Moko','Loyal Legion','Mucca Osteria','Renata Restaurant',
    'Bullard Texas BBQ','Cheryl''s on 12th','Mediterranean Exploration','The Waiting Room',
    'Lechon','Apizza Scholls','Lovely''s Fifty Fifty','Ned Ludd',
    'Broder Nord','Broder Öst','Screen Door','Tin Shed Garden Café',
    'Pine State Biscuits','Gravy Restaurant','Bijou Café','Slappy Cakes',
    'Besaw''s Restaurant','Byways Café','Original Pancake House','Zell''s Café',
    'Café Nell','Bar Avignon','Taqueria Santa Cruz','Racion Restaurant',
    'Paley''s Place','Genoa Restaurant','Higgins Restaurant','Southpark Seafood',
    'Jake''s Famous Crawfish','McCormick & Schmick''s','Ringside Steakhouse','Ruth''s Chris PDX',
    'El Gaucho Portland','Chart House Restaurant','Castagna Restaurant','Tabla Restaurant',
    'Pok Pok Restaurant','Lúc Lắc Vietnamese','Tasty n Alder','Little Bird Bistro',
    'Irving Street Kitchen','Bluehour Restaurant','Meriwether''s Restaurant','Serratto Restaurant',
    'Wildwood Restaurant','Laurelhurst Market','Beast Restaurant','Coquine Restaurant',
    'Gado Gado','Tusk PDX','Eem Restaurant','Scotch Lodge',
    'Luce PDX','Expatriate Bar','Navarre Restaurant','Bar Mingo',
    'Nostrana PDX','Aviary Restaurant','Ox PDX','Olympic Provisions',
    'Olympia Provisions SE','Salt & Straw Eastside','Nuvrei Patisserie','Ken''s Artisan Bakery',
    'Grand Central Bakery','Tabor Bread','Little T Baker','Roman Candle Bakery',
    'Pearl Bakery','Spielman Bagels','Dave''s Killer Bread Café','St Honoré Boulangerie',
    'Pix Patisserie','Pinolo Gelato','Ruby Jewel Ice Cream','Salt & Straw NW',
    -- Hotels & Hospitality
    'Ace Hotel Portland','Hotel Lucia','Hotel deLuxe','Hotel Vintage Portland',
    'The Nines Hotel','Hotel Modera','White Stag Inn','River''s Edge Hotel',
    'Kimpton Riverplace','Embassy Suites Portland','Hilton Portland','Marriott Portland',
    'Westin Portland','Sheraton Portland','Hyatt Regency Portland','Hotel Indigo',
    'Mark Spencer Hotel','Jupiter Hotel','Sentinel Hotel','Hotel Eastlund',
    'The Heathman Hotel','The Governor Hotel','Benson Hotel','Crystal Hotel',
    'Porter Portland','Woodlark Hotel','Duniway Portland','Graduate Portland',
    'Provenance Hotels','Inn at Northrup Station','Kennedy School McMenamins','Edgefield McMenamins',
    'Grand Lodge McMenamins','Cornelius Pass McMenamins','Mission Theater McMenamins','Crystal Ballroom Hotel',
    'Courtyard Portland','Residence Inn Portland','TownePlace Suites','Hampton Inn Portland',
    'Aloft Portland','Element Portland','AC Hotel Portland','Moxy Portland',
    'Holiday Inn Portland','Best Western Plus','Quality Inn Portland','Comfort Suites PDX',
    'Canopy by Hilton','Curio Collection Hilton','Tapestry Collection Hilton','Home2 Suites Portland',
    'Staybridge Suites PDX','Extended Stay Portland','Homewood Suites PDX','SpringHill Suites',
    'Fairfield Inn Portland','Four Points Portland','Delta Hotels Portland','Autograph Collection',
    'The Society Hotel','McMenamins Edgefield','Timberline Lodge','Mt Hood Inn',
    'Salishan Coastal Lodge','Skamania Lodge','Sunriver Resort','Black Butte Ranch',
    'Crater Lake Lodge','Stephanie Inn Cannon Beach','Surfsand Resort','Inn at Haystack Rock',
    -- Grocery & Markets
    'New Seasons Market NW','New Seasons Market SE','New Seasons Arbor Lodge','New Seasons Concordia',
    'Zupan''s Markets Burnside','Zupan''s Markets NW','Market of Choice Eugene','Market of Choice Corvallis',
    'Whole Foods Pearl','Whole Foods Cedar Hills','Whole Foods Division','Natural Grocers Portland',
    'Alberta Co-op Grocery','People''s Food Co-op','Food Front Co-op','Ecotrust Farm Hub',
    'Pastaworks','Providore Fine Foods','Elephants Delicatessen','City Market NW',
    'Gartner''s Country Meat Market','Foster & Dobbs','Cheese Bar PDX','Rubinette Produce',
    'Ocean Beauty Seafoods','Flying Fish Company','Newman''s Fish Company','Pacific Seafood',
    'World Foods PDX','Uwajimaya Portland','Fubonn Shopping Center','H Mart Portland',
    'Sheridan Fruit Co','Bob''s Red Mill Store','Bob''s Whole Grain Store','Meadows Coffee & Spice',
    'Martinotti''s Café & Deli','City Liquidators','Roth''s Fresh Markets','Lamb''s Markets',
    'Harry & David','Stash Tea Company','Moonstruck Chocolate','Xocolatl de David',
    'Alma Chocolate','Cacao Portland','CocoVaa Chocolatier','Missionary Chocolates',
    'Ristretto Roasters Cafe','Heart Roasters NE','Coava NE','Coffee Plant NE',
    -- Non-traditional & VIP
    'Powell''s Books','Powell''s Books Beaverton','Reading Frenzy','Broadway Books',
    'Annie Bloom''s Books','In Other Words','St Johns Booksellers','Wieden+Kennedy',
    'Instrument Agency','Citizen Design','Ziba Design','Pear Bureau Northwest',
    'Pendleton Woolen Mills','Columbia Sportswear HQ','Nike World HQ Café','Adidas North America',
    'Intel Jones Farm Café','Intel Ronler Acres','Oregon Health Sciences Café','OHSU Marquam Café',
    'Portland State University','Reed College Café','Lewis & Clark Coffee','University of Portland Café',
    'Oregon Museum of Science','Portland Art Museum Café','Oregon Zoo Café','World Forestry Center',
    'Pittock Mansion','Lan Su Chinese Garden Café','Powell''s City of Books Café','Multnomah County Library'
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
  biz_count INT := 0;
  ind_count INT := 0;
BEGIN
  FOR rec IN
    SELECT customer_id, customer_category
    FROM customers
    WHERE facility_id = 'demo-kailua-roastery'
    ORDER BY customer_id
  LOOP
    IF rec.customer_category = 'Online' THEN
      -- Individual / retail DTC
      UPDATE customers SET name_company =
        first_names[(ind_count % 100) + 1] || ' ' ||
        last_names[((ind_count / 100) % 100) + 1]
      WHERE customer_id = rec.customer_id;
      ind_count := ind_count + 1;
    ELSE
      -- Business account (Cafe, Restaurant, Hospitality, Grocery, Non Traditional, VIP)
      UPDATE customers SET name_company =
        biz_names[(biz_count % array_length(biz_names, 1)) + 1]
      WHERE customer_id = rec.customer_id;
      biz_count := biz_count + 1;
    END IF;
  END LOOP;
END $$;

SET session_replication_role = DEFAULT;
