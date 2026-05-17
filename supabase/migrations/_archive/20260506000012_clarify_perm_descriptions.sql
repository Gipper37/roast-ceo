-- Tighten two permission descriptions that were misleading users:
--
--   customer.edit  — listed "payment terms" as one of the things this
--                    permission covers, but payment-terms editing is
--                    its own permission (`payments.terms_edit`, gated
--                    to manager+ AND plan-tier'd to Enterprise+). Keep
--                    them clearly separate.
--
--   inventory.edit — claimed users can edit "par" and "restock" via
--                    inventory rows, but those columns are computed
--                    from the assigned restock category + daily_usage.
--                    The actually-editable per-row fields are bag size,
--                    supplier, restock category, name, and is_active.

UPDATE permissions
SET description = 'Update name, address, contacts, sales area, and other customer profile fields. Payment-terms changes are gated separately under "Edit customer payment terms".'
WHERE permission_id = 'customer.edit';

UPDATE permissions
SET description = 'Edit per-row inventory fields: bag size, supplier, restock category, item name, and active/archived status. Par + restock-level are auto-calculated from the assigned restock category and daily usage.'
WHERE permission_id = 'inventory.edit';
