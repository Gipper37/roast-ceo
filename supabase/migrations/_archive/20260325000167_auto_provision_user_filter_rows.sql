-- ── Trigger function: provision filter rows for new team member ──────────────
CREATE OR REPLACE FUNCTION public.provision_user_filter_rows()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    -- Skip if no email (can't scope user rows without it)
    IF NEW.email IS NULL THEN RETURN NEW; END IF;

    -- product_filter
    INSERT INTO public.product_filter
        (products_filter_id, company_id, facility_id, user_email, created_by)
    VALUES
        (gen_random_uuid()::text, NEW.company_id, NEW.facility_id, NEW.email, NEW.team_member_id)
    ON CONFLICT DO NOTHING;

    -- sales_data_filter
    INSERT INTO public.sales_data_filter
        (sales_data_filter_id, company_id, facility_id, user_email, created_by)
    VALUES
        (gen_random_uuid()::text, NEW.company_id, NEW.facility_id, NEW.email, NEW.team_member_id)
    ON CONFLICT DO NOTHING;

    -- customer_sales_filter
    INSERT INTO public.customer_sales_filter
        (sales_filter_id, company_id, facility_id, user_email, created_by)
    VALUES
        (gen_random_uuid()::text, NEW.company_id, NEW.facility_id, NEW.email, NEW.team_member_id)
    ON CONFLICT DO NOTHING;

    -- blending_worksheet
    INSERT INTO public.blending_worksheet
        (blending_id, company_id, facility_id, user_email, created_by)
    VALUES
        (gen_random_uuid()::text, NEW.company_id, NEW.facility_id, NEW.email, NEW.team_member_id)
    ON CONFLICT DO NOTHING;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_provision_user_filter_rows
AFTER INSERT ON public.team
FOR EACH ROW
EXECUTE FUNCTION public.provision_user_filter_rows();

-- ── Backfill existing team members ───────────────────────────────────────────
DO $$
DECLARE
    t RECORD;
BEGIN
    FOR t IN
        SELECT team_member_id, email, company_id, facility_id
        FROM public.team
        WHERE email IS NOT NULL
    LOOP
        -- product_filter
        INSERT INTO public.product_filter
            (products_filter_id, company_id, facility_id, user_email, created_by)
        VALUES
            (gen_random_uuid()::text, t.company_id, t.facility_id, t.email, t.team_member_id)
        ON CONFLICT DO NOTHING;

        -- sales_data_filter
        INSERT INTO public.sales_data_filter
            (sales_data_filter_id, company_id, facility_id, user_email, created_by)
        VALUES
            (gen_random_uuid()::text, t.company_id, t.facility_id, t.email, t.team_member_id)
        ON CONFLICT DO NOTHING;

        -- customer_sales_filter
        IF NOT EXISTS (
            SELECT 1 FROM public.customer_sales_filter
            WHERE user_email = t.email AND facility_id = t.facility_id
        ) THEN
            INSERT INTO public.customer_sales_filter
                (sales_filter_id, company_id, facility_id, user_email, created_by)
            VALUES
                (gen_random_uuid()::text, t.company_id, t.facility_id, t.email, t.team_member_id);
        END IF;

        -- blending_worksheet
        IF NOT EXISTS (
            SELECT 1 FROM public.blending_worksheet
            WHERE user_email = t.email AND facility_id = t.facility_id
        ) THEN
            INSERT INTO public.blending_worksheet
                (blending_id, company_id, facility_id, user_email, created_by)
            VALUES
                (gen_random_uuid()::text, t.company_id, t.facility_id, t.email, t.team_member_id);
        END IF;
    END LOOP;
END;
$$;
