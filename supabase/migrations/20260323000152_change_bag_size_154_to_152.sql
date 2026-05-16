-- Migration 00152: Change standard green coffee bag size from 154 to 152 lbs
-- Updates: bag_sizes, standard_parameters, company_parameters, coffee_source, coffee_inventory
-- Triggers on coffee_inventory cascade recalculations automatically

-- 1. Add 152 to bag_sizes lookup table
INSERT INTO public.bag_sizes (bag_size_id, label)
VALUES ('152', '152')
ON CONFLICT (bag_size_id) DO NOTHING;

-- 2. Update standard_parameters fallback value
UPDATE public.standard_parameters
SET amount = 152
WHERE parameters_id = '66526a57';

-- 3. Update all company_parameters (all companies that had 154)
UPDATE public.company_parameters
SET value_number = 152
WHERE parameter_id = '66526a57' AND value_number = 154;

-- 4. Update coffee_source (triggers trg_propagate_coffee_source_bag_size → pushes to coffee_inventory)
UPDATE public.coffee_source
SET bag_size = '152'
WHERE bag_size = '154';

-- 5. Update any remaining coffee_inventory rows not reached by the trigger above
UPDATE public.coffee_inventory
SET bag_size = '152'
WHERE bag_size = '154';
