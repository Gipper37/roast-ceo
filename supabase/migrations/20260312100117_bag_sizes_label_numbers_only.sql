-- Migration 00117: Strip "lbs" unit suffix from bag_sizes labels
--
-- Labels were '154 lbs', '132 lbs', '100 lbs'.
-- AppSheet uses a dependent display formula to append the correct unit
-- (lbs, kg, etc.) based on facility — so the label should be the plain number only.

UPDATE public.bag_sizes SET label = '154' WHERE bag_size_id = '154';
UPDATE public.bag_sizes SET label = '132' WHERE bag_size_id = '132';
UPDATE public.bag_sizes SET label = '100' WHERE bag_size_id = '100';
