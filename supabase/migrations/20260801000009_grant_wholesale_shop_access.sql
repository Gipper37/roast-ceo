-- Imported customers can be invited to the wholesale shop without 367 clicks first.
--
-- No customer STRATA has ever imported had shop_access set — the importer never
-- touched the column — so every one of MCR's 367 shows "No access granted". To
-- get a single customer shopping you had to grant access, send an invite, and
-- have them accept. Step one was pure friction for a roaster who just brought
-- their whole book across.
--
-- 🔴 THIS OPENS NOTHING BY ITSELF. Access is two independent things:
--     shop_access   — which catalog tier a customer is ELIGIBLE for
--     customer_users — an actual login, created by invitation and acceptance
-- MCR has zero customer_users rows. Granting shop_access cannot expose a price
-- or let anyone in; it only marks who may be invited. The invitation remains the
-- real gate, and it is unchanged.
--
-- WHOLESALE ONLY. VIP usually carries special pricing and stays a deliberate
-- act — granting it in bulk would hand every account a tier nobody chose for
-- them.
--
-- Customers who already have some access are left exactly as they are; this only
-- fills in the ones with none.
--
-- 🔴 SCOPED TO MAUI COFFEE ROASTERS. The first draft of this had no company
-- filter and would have granted access to 2,028 customers across every tenant —
-- including 781 of Social Hour's, who have live shop logins. A one-time
-- correction belongs to the roaster whose book was just imported and who asked
-- for it; it is not a licence to rewrite another company's customer list.
-- Going forward the DEFAULT applies to everyone (the importer and
-- createCustomer both grant wholesale on create) — that is product behaviour,
-- and it only ever affects rows created from here on.

begin;

update public.customers
   set shop_access = array['wholesale']
 where company_id = '9ShiyDAXhV'
   and (shop_access is null or cardinality(shop_access) = 0)
   and coalesce(is_active, true);

commit;

notify pgrst, 'reload schema';
