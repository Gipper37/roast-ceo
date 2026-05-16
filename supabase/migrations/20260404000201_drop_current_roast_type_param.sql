-- Drop current_roast_type from company_parameters and standard_parameters
-- Roast type is dictated by roast_recipes.roast_type, not a facility-wide parameter

DELETE FROM company_parameters WHERE parameter_id = 'current_roast_type';
DELETE FROM standard_parameters WHERE parameters_id = 'current_roast_type';
