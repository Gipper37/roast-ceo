-- MCR Artisan blends → roast_recipes + recipe_components + product links
BEGIN;
SET LOCAL app.skip_audit = 'true';
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-lokelani-blend', 'Lokelani Blend', 'Pre-Blend', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-fe61f78f519a58a0', 'rcp-mcr-lokelani-blend', 0.55, 'orig_c655bcaf99a986b1', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-c201bd0fa4c150bf', 'rcp-mcr-lokelani-blend', 0.45, 'orig_bd7157c2ff0a76b3', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-euro-dark', 'Euro Dark', 'Single Origin', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-1f0776e00a8855d2', 'rcp-mcr-euro-dark', 1.0, 'orig_c655bcaf99a986b1', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-flavor', 'Flavor', 'Single Origin', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-d725a6db45cb5d4d', 'rcp-mcr-flavor', 1.0, 'orig_c655bcaf99a986b1', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-mb-lt', 'MB LT', 'Pre-Blend', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-738484f32f835d2e', 'rcp-mcr-mb-lt', 0.45, 'orig_d393e3392710921a', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-f081288f0889519b', 'rcp-mcr-mb-lt', 0.45, 'orig_28d3a9afb33fb94a', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-4a81ffafdddf5320', 'rcp-mcr-mb-lt', 0.1, 'orig_142ffc976e750f22', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-mb-dk', 'MB DK', 'Pre-Blend', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-b943c69105a15a12', 'rcp-mcr-mb-dk', 0.45, 'orig_d393e3392710921a', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-efcf27f4ab1d58bd', 'rcp-mcr-mb-dk', 0.45, 'orig_28d3a9afb33fb94a', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-098b65855840522a', 'rcp-mcr-mb-dk', 0.1, 'orig_142ffc976e750f22', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-hoala-blend', 'Hoala Blend', 'Pre-Blend', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-0f0649d004025428', 'rcp-mcr-hoala-blend', 0.585, 'orig_c655bcaf99a986b1', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-402e930796d15a49', 'rcp-mcr-hoala-blend', 0.415, 'orig_d669c72ce18c7651', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-french-roast', 'French Roast', 'Pre-Blend', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-5ef315e9b5bc51dd', 'rcp-mcr-french-roast', 0.5, 'orig_d393e3392710921a', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-af2a8a505022594d', 'rcp-mcr-french-roast', 0.5, 'orig_28d3a9afb33fb94a', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-organic-dk', 'Organic DK', 'Single Origin', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-7d657de870895f24', 'rcp-mcr-organic-dk', 1.0, 'orig_0d75323d13d7e2fe', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-organic-med', 'Organic Med', 'Single Origin', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-b1422ce2887752b5', 'rcp-mcr-organic-med', 1.0, 'orig_0d75323d13d7e2fe', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-organic-lt', 'Organic LT', 'Single Origin', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-52059bd344115d89', 'rcp-mcr-organic-lt', 1.0, 'orig_0d75323d13d7e2fe', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-organic-espresso', 'Organic Espresso', 'Single Origin', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-98804e6381295a6d', 'rcp-mcr-organic-espresso', 1.0, 'orig_0d75323d13d7e2fe', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-organic-french', 'Organic French', 'Single Origin', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-5193ce672439542d', 'rcp-mcr-organic-french', 1.0, 'orig_0d75323d13d7e2fe', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-espresso', 'Espresso', 'Pre-Blend', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-f23dfaa94e595f97', 'rcp-mcr-espresso', 0.508, 'orig_c655bcaf99a986b1', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-b7db4b50af065e8a', 'rcp-mcr-espresso', 0.36, 'orig_d393e3392710921a', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-7dfbe83175a6588f', 'rcp-mcr-espresso', 0.132, 'orig_17c8424053723e32', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-club-imua', 'Club Imua', 'Single Origin', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-17fa293ea77a59ec', 'rcp-mcr-club-imua', 1.0, 'orig_d5456517bf131c45', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-puk-sup-blend', 'Puk Sup Blend', 'Single Origin', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-84e732f74b8a5b9b', 'rcp-mcr-puk-sup-blend', 1.0, 'orig_c655bcaf99a986b1', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-sumatra-dk', 'Sumatra DK', 'Single Origin', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-6a6238dba9785803', 'rcp-mcr-sumatra-dk', 1.0, 'orig_17c8424053723e32', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-nokaoi', 'Nokaoi', 'Pre-Blend', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-557f03563afd5a25', 'rcp-mcr-nokaoi', 0.95, 'orig_d393e3392710921a', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-e7eac3cf06dc5232', 'rcp-mcr-nokaoi', 0.05, 'orig_93f7f73f959de942', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-colombian-dark', 'Colombian Dark', 'Single Origin', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-ebe3939f59d757ea', 'rcp-mcr-colombian-dark', 1.0, 'orig_d393e3392710921a', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-mb-med-2oz', 'MB Med (2oz)', 'Pre-Blend', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-17b94f9d93a05cb6', 'rcp-mcr-mb-med-2oz', 0.45, 'orig_c655bcaf99a986b1', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-45aac7c1f80a576d', 'rcp-mcr-mb-med-2oz', 0.45, 'orig_28d3a9afb33fb94a', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-2066e5cded365612', 'rcp-mcr-mb-med-2oz', 0.1, 'orig_142ffc976e750f22', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-house-blend', 'House Blend', 'Pre-Blend', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-f839a77c08db5715', 'rcp-mcr-house-blend', 0.5, 'orig_c655bcaf99a986b1', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-831b53fe40e756d2', 'rcp-mcr-house-blend', 0.5, 'orig_28d3a9afb33fb94a', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-fresh-trade', 'Fresh Trade', 'Single Origin', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-a14e040a20da5258', 'rcp-mcr-fresh-trade', 1.0, 'orig_28d3a9afb33fb94a', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-sw-sup-dk', 'SW Sup DK', 'Single Origin', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-75cfea3964715252', 'rcp-mcr-sw-sup-dk', 1.0, 'orig_b3890561c1c3ba25', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-sw-sup-lt', 'SW Sup LT', 'Single Origin', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-7d2aa5e39d145aa0', 'rcp-mcr-sw-sup-lt', 1.0, 'orig_b3890561c1c3ba25', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-maui-red-bag', 'Maui Red Bag', 'Single Origin', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-0540604acf785533', 'rcp-mcr-maui-red-bag', 1.0, 'orig_142ffc976e750f22', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-mama-s-maui-moka', 'Mama''s Maui Moka', 'Pre-Blend', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-727b67121f2f59bb', 'rcp-mcr-mama-s-maui-moka', 0.7, 'orig_142ffc976e750f22', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-d9ed8e917f3c5f46', 'rcp-mcr-mama-s-maui-moka', 0.3, 'orig_0798b3ed3a9e31a1', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-mama-s-maui-red', 'Mama''s Maui Red', 'Pre-Blend', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-1b42ff58d4a15bb1', 'rcp-mcr-mama-s-maui-red', 0.5, 'orig_b3890561c1c3ba25', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-09c4ef3b1b2f5857', 'rcp-mcr-mama-s-maui-red', 0.5, 'orig_142ffc976e750f22', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-maui-moka', 'Maui Moka', 'Single Origin', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-9dc451e08d5e5627', 'rcp-mcr-maui-moka', 1.0, 'orig_142ffc976e750f22', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-maui-pea-lt', 'Maui Pea LT', 'Single Origin', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-e95953f6d41950c5', 'rcp-mcr-maui-pea-lt', 1.0, 'orig_142ffc976e750f22', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-maui-pea-dk', 'Maui Pea DK', 'Single Origin', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-f1e3854a77de5861', 'rcp-mcr-maui-pea-dk', 1.0, 'orig_142ffc976e750f22', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-red-rooster', 'Red Rooster', 'Single Origin', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-bf3742b2718455e6', 'rcp-mcr-red-rooster', 1.0, 'orig_142ffc976e750f22', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-yellow-cat', 'Yellow Cat', 'Single Origin', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-694c12d97bf25dd8', 'rcp-mcr-yellow-cat', 1.0, 'orig_142ffc976e750f22', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-espresso-decaf', 'Espresso Decaf', 'Single Origin', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-9ba492eefff5500c', 'rcp-mcr-espresso-decaf', 1.0, 'orig_0d75323d13d7e2fe', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-flavor-decaf', 'Flavor Decaf', 'Single Origin', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-d6304589544450c0', 'rcp-mcr-flavor-decaf', 1.0, 'orig_0d75323d13d7e2fe', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-mcr-hi-blend-decaf', 'MCR HI Blend Decaf', 'Pre-Blend', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-b20a089ecc4a5e4e', 'rcp-mcr-mcr-hi-blend-decaf', 0.95, 'orig_0d75323d13d7e2fe', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-a625497ac75f5a13', 'rcp-mcr-mcr-hi-blend-decaf', 0.05, 'orig_2bb4bb4cfe71072a', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-french-decaf', 'French Decaf', 'Single Origin', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-0634922e190851d6', 'rcp-mcr-french-decaf', 1.0, 'orig_0d75323d13d7e2fe', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-pacific-pea-blend', 'Pacific Pea Blend', 'Pre-Blend', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-b60f666627a25f33', 'rcp-mcr-pacific-pea-blend', 0.9, 'orig_93f7f73f959de942', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-166ad6d3dc9f5b97', 'rcp-mcr-pacific-pea-blend', 0.1, 'orig_142ffc976e750f22', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-pacific-blend', 'Pacific Blend', 'Pre-Blend', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-918bf1df488150bd', 'rcp-mcr-pacific-blend', 0.95, 'orig_17c8424053723e32', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-3a3bed005e305308', 'rcp-mcr-pacific-blend', 0.05, 'orig_2bb4bb4cfe71072a', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-sw-pea-lt', 'SW Pea LT', 'Single Origin', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-0d767e0beccd5115', 'rcp-mcr-sw-pea-lt', 1.0, 'orig_93f7f73f959de942', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-nicbeans-kona', 'NicBeans Kona', 'Single Origin', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-ced548d5a8815c2c', 'rcp-mcr-nicbeans-kona', 1.0, 'orig_2bb4bb4cfe71072a', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-kona-decaf', 'Kona Decaf', 'Pre-Blend', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-4fb89e265f805740', 'rcp-mcr-kona-decaf', 0.9, 'orig_0d75323d13d7e2fe', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-1d6252770f71539c', 'rcp-mcr-kona-decaf', 0.1, 'orig_2bb4bb4cfe71072a', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-kona-bl-med', 'Kona BL Med', 'Pre-Blend', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-cc4a5874422059af', 'rcp-mcr-kona-bl-med', 0.45, 'orig_d393e3392710921a', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-5713a1a873da5280', 'rcp-mcr-kona-bl-med', 0.45, 'orig_28d3a9afb33fb94a', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-87fc815f0e135fbe', 'rcp-mcr-kona-bl-med', 0.1, 'orig_2bb4bb4cfe71072a', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-kona-bl-dk', 'Kona BL DK', 'Pre-Blend', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-a557a7b904ae5d30', 'rcp-mcr-kona-bl-dk', 0.45, 'orig_d393e3392710921a', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-d91d210776e75d4d', 'rcp-mcr-kona-bl-dk', 0.45, 'orig_28d3a9afb33fb94a', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-fc99739d97075adf', 'rcp-mcr-kona-bl-dk', 0.1, 'orig_2bb4bb4cfe71072a', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-kona-bl-lt', 'Kona BL LT', 'Pre-Blend', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-89b789d0b4955414', 'rcp-mcr-kona-bl-lt', 0.45, 'orig_d393e3392710921a', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-4fcbca45e070532e', 'rcp-mcr-kona-bl-lt', 0.45, 'orig_28d3a9afb33fb94a', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-06dc6d9e465652ef', 'rcp-mcr-kona-bl-lt', 0.1, 'orig_2bb4bb4cfe71072a', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-kona-castaway-reserve', 'Kona Castaway (Reserve)', 'Single Origin', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-e276f690deeb5c1f', 'rcp-mcr-kona-castaway-reserve', 1.0, 'orig_2bb4bb4cfe71072a', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-kona-est-dk', 'Kona Est DK', 'Single Origin', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-26c294a717ec562c', 'rcp-mcr-kona-est-dk', 1.0, 'orig_2bb4bb4cfe71072a', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-kona-est-lt', 'Kona Est LT', 'Single Origin', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-b37860cf7f775e74', 'rcp-mcr-kona-est-lt', 1.0, 'orig_2bb4bb4cfe71072a', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-kona-pea-med', 'Kona Pea Med', 'Single Origin', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-70994301a4af54e2', 'rcp-mcr-kona-pea-med', 1.0, 'orig_2bb4bb4cfe71072a', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-mcr-hi-blend', 'MCR HI Blend', 'Pre-Blend', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-5295375b3fd25f58', 'rcp-mcr-mcr-hi-blend', 0.9, 'orig_b3890561c1c3ba25', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-7220e852fd905027', 'rcp-mcr-mcr-hi-blend', 0.1, 'orig_2bb4bb4cfe71072a', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-kau', 'Kau', 'Single Origin', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-99b13d1f5e545605', 'rcp-mcr-kau', 1.0, 'orig_afb785641116ec03', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-mama-s-espresso', 'Mama''s Espresso', 'Pre-Blend', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-bd6bb51e92e15506', 'rcp-mcr-mama-s-espresso', 0.45, 'orig_d393e3392710921a', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-4ec9af7849cd574e', 'rcp-mcr-mama-s-espresso', 0.45, 'orig_c655bcaf99a986b1', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-811545c39ca75be7', 'rcp-mcr-mama-s-espresso', 0.1, 'orig_afb785641116ec03', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-nobu-espresso', 'Nobu Espresso', 'Pre-Blend', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-6f647434012d5e49', 'rcp-mcr-nobu-espresso', 0.5, 'orig_afb785641116ec03', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-9bb2b9f3647d57e1', 'rcp-mcr-nobu-espresso', 0.3, 'orig_28d3a9afb33fb94a', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-5bc3486b33295fc2', 'rcp-mcr-nobu-espresso', 0.2, 'orig_c655bcaf99a986b1', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-org-kona-bl-med', 'Org Kona Bl Med', 'Pre-Blend', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-a64fe95ec1d654f4', 'rcp-mcr-org-kona-bl-med', 0.9, 'orig_5e487c2d0035d0d4', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-d9bf7a2a57805cec', 'rcp-mcr-org-kona-bl-med', 0.1, 'orig_2bb4bb4cfe71072a', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, created_at, updated_at, created_by, is_active)
VALUES ('rcp-mcr-org-kona-bl-dk', 'ORG Kona BL DK', 'Pre-Blend', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV', true)
ON CONFLICT (recipe_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-2d8173b529905454', 'rcp-mcr-org-kona-bl-dk', 0.9, 'orig_5e487c2d0035d0d4', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, percentage, coffee_item, company_id, facility_id, created_at, updated_at, created_by)
VALUES ('rcc-bbda9a63cef256cf', 'rcp-mcr-org-kona-bl-dk', 0.1, 'orig_2bb4bb4cfe71072a', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (component_id) DO NOTHING;

-- ── Link products to recipes (matched groups) ──
UPDATE public.products SET recipe_id = 'rcp-mcr-lokelani-blend' WHERE company_id = '9ShiyDAXhV' AND group_id = 'e312f6b7-a862-42d8-8854-13a43e4854a4' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-euro-dark' WHERE company_id = '9ShiyDAXhV' AND group_id = '6906006d-de70-4de6-8c5d-7c4c762ddb6a' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-flavor' WHERE company_id = '9ShiyDAXhV' AND group_id = '5827f392-d083-4eef-8235-1dbcdf384d55' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-hoala-blend' WHERE company_id = '9ShiyDAXhV' AND group_id = 'a65a9aec-ba8e-4da2-844a-ef89e05d85d3' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-french-roast' WHERE company_id = '9ShiyDAXhV' AND group_id = '76d414bf-6501-4f93-8a29-fde19368efa9' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-espresso' WHERE company_id = '9ShiyDAXhV' AND group_id = '2697c180-0451-4f16-8401-7292984cb331' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-club-imua' WHERE company_id = '9ShiyDAXhV' AND group_id = '1c285e1f-1eeb-4898-8833-09f51a306721' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-puk-sup-blend' WHERE company_id = '9ShiyDAXhV' AND group_id = '34a49d90-5dc5-4589-87cb-b7d735be29fb' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-sumatra-dk' WHERE company_id = '9ShiyDAXhV' AND group_id = 'a73416f6-70b0-4d93-87d3-8a6369ee5af4' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-nokaoi' WHERE company_id = '9ShiyDAXhV' AND group_id = '4d12031e-c742-43e8-8f57-7f0c447068b1' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-colombian-dark' WHERE company_id = '9ShiyDAXhV' AND group_id = 'd1a00e39-890f-4fa3-8d8a-f16e0b8d9d0e' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-house-blend' WHERE company_id = '9ShiyDAXhV' AND group_id = 'f012f063-84cf-461e-8f77-52ef60678da9' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-fresh-trade' WHERE company_id = '9ShiyDAXhV' AND group_id = 'af7381f1-4448-4c65-8bf1-31fbd41ab6b3' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-sw-sup-dk' WHERE company_id = '9ShiyDAXhV' AND group_id = '576988f0-f1f9-4638-8bde-4815c6df97e0' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-sw-sup-lt' WHERE company_id = '9ShiyDAXhV' AND group_id = '0dbf5ce3-436b-4a8f-803d-34a8431a6e15' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-maui-red-bag' WHERE company_id = '9ShiyDAXhV' AND group_id = '80869405-03a5-4811-8032-923bef52bf28' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-maui-moka' WHERE company_id = '9ShiyDAXhV' AND group_id = '12f19a24-91f0-4015-844a-46a638620cf3' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-maui-pea-lt' WHERE company_id = '9ShiyDAXhV' AND group_id = '97655176-be7e-4a63-8684-ddac9206fdd0' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-maui-pea-dk' WHERE company_id = '9ShiyDAXhV' AND group_id = '9e3a2ff9-dfe2-4c7a-891e-238b0e8a13f7' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-red-rooster' WHERE company_id = '9ShiyDAXhV' AND group_id = 'aec48ce1-0f16-4875-84a1-27a941833644' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-yellow-cat' WHERE company_id = '9ShiyDAXhV' AND group_id = '8b97b37d-39e3-41ee-876d-dfd08d1210f2' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-espresso-decaf' WHERE company_id = '9ShiyDAXhV' AND group_id = 'a402cdf6-e405-4888-8355-356652733a18' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-flavor-decaf' WHERE company_id = '9ShiyDAXhV' AND group_id = 'fce3c213-4312-4d9d-8e3b-b53b31d68272' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-mcr-hi-blend-decaf' WHERE company_id = '9ShiyDAXhV' AND group_id = '6e182c63-9bea-41ed-879b-9fc148ede8fb' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-french-decaf' WHERE company_id = '9ShiyDAXhV' AND group_id = '2ceb206d-b50b-4c2b-87b1-8f83e5e7c590' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-pacific-pea-blend' WHERE company_id = '9ShiyDAXhV' AND group_id = '324918dd-2603-4e3c-868b-869c25bac0f4' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-pacific-blend' WHERE company_id = '9ShiyDAXhV' AND group_id = '00c8c2ad-e62b-4e43-8031-282301bd2ac3' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-nicbeans-kona' WHERE company_id = '9ShiyDAXhV' AND group_id = '4f311a31-dd51-4317-8eb7-79f8492c22ad' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-kona-decaf' WHERE company_id = '9ShiyDAXhV' AND group_id = 'e2336191-b1eb-4b5a-8b8a-37910ee861ae' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-kona-bl-med' WHERE company_id = '9ShiyDAXhV' AND group_id = '1c90dc79-7d17-4bda-8dbe-1ba445b76ccf' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-kona-bl-dk' WHERE company_id = '9ShiyDAXhV' AND group_id = 'bf224475-f792-48d0-800c-c9e886a23025' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-kona-bl-lt' WHERE company_id = '9ShiyDAXhV' AND group_id = '8a9a0c25-5086-47ea-86c7-56a93e7e0fdc' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-kona-castaway-reserve' WHERE company_id = '9ShiyDAXhV' AND group_id = '96c791ca-5314-4659-8438-67fa3c171aff' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-kona-est-dk' WHERE company_id = '9ShiyDAXhV' AND group_id = '97caa757-dda0-4079-8bee-dd00fb8fc8f6' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-kona-est-lt' WHERE company_id = '9ShiyDAXhV' AND group_id = '3130167e-e7eb-44e0-8929-5ec41376a2b6' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-kona-pea-med' WHERE company_id = '9ShiyDAXhV' AND group_id = '59486988-61ae-4412-88ea-501f3f7b0539' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-mcr-hi-blend' WHERE company_id = '9ShiyDAXhV' AND group_id = 'e05fa45b-71a6-4eed-8b88-0fde812f2f91' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-kau' WHERE company_id = '9ShiyDAXhV' AND group_id = '0046e157-d821-4fb7-8491-0ea826b96451' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-mama-s-espresso' WHERE company_id = '9ShiyDAXhV' AND group_id = 'bb4c8c13-c400-4d88-8144-b9fb3c93bff2' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-nobu-espresso' WHERE company_id = '9ShiyDAXhV' AND group_id = '8fe36eff-4341-4ba5-8d24-8dd83204b776' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-org-kona-bl-med' WHERE company_id = '9ShiyDAXhV' AND group_id = '3b6bd1ac-8446-4871-8245-85e3b224db59' AND is_active = true;
UPDATE public.products SET recipe_id = 'rcp-mcr-org-kona-bl-dk' WHERE company_id = '9ShiyDAXhV' AND group_id = '1a681c64-dc73-4e5e-8892-e75c9c9edf7b' AND is_active = true;
COMMIT;
