-- The delete gate matches the app, and the counters ALL ask.
--
-- Three gaps the completeness critic found in 20260910000018 itself.
--
-- 1. 🔴 I GATED ONE OF THREE COUNTERS. …0018's header says "the three definer
--    counters … now ask for the permission their own use implies" and then only
--    rewrote sync_invoice_next_seq. allocate_invoice_number and
--    allocate_credit_memo_number kept a tenancy-only test, and they are
--    PostgREST RPCs — so any member of the tenant could still burn invoice and
--    credit-memo numbers. The claim in that commit message was wrong; this makes
--    it true.
--
-- 2. 🔴 MY DELETE GATE BROKE THE QUEUE AND INFLATED GREEN. …0018 made every
--    DELETE on roast_log require roast.delete_completed. The app has always had
--    a two-tier rule (roast/actions.ts deleteRoast): a COMPLETED roast —
--    roast_date set AND some real content — needs roast.delete_completed, while
--    a STAGED or junk row rides on roast.log, which is what lets an assistant
--    roaster clear the queue. Worse, delete_roasts restores the green BEFORE it
--    deletes: with the delete filtered to zero rows by my policy, a roastmaster
--    clearing a staged row credited coffee_inventory_purchased.remaining_lbs and
--    the roast stayed. Silent inventory inflation, caused by the fix.
--    Now: the policy mirrors the app's two tiers, and delete_roasts refuses
--    up front — before it touches inventory — rather than discovering the
--    refusal in a zero-row DELETE.
--
-- 3. The legacy-import carve-out on INSERT is deliberate and stays: the
--    QuickBooks importer creates numbered, posted history rows under
--    config.import_data, and its write is a plain INSERT (qbImportActions.ts
--    :1722), which …0018 checked and allows. A holder of that key can therefore
--    still CREATE a fake historical invoice; they can no longer flip the flag
--    onto a live receivable, which was the finding. Recorded, not closed.

begin;

-- ═══ 1. the other two counters ════════════════════════════════════════════
create or replace function public.allocate_invoice_number(p_company_id text)
returns table(invoice_sequence bigint, invoice_number text)
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_seq       bigint;
  v_prefix    text;
  v_pad       integer;
  v_mode      text;
  v_candidate text;
  v_jumped    boolean := false;
  v_guard     integer := 0;
begin
  -- Issuing (invoice.send), configuring billing (commit_cutover, apply_open_ar)
  -- or carrying history in (the QuickBooks importer). Anyone else has no
  -- business advancing the number.
  perform public.guard_counter_caller(
    p_company_id, array['invoice.send', 'billing.configure', 'config.import_data']);

  insert into public.billing_settings
    (company_id, invoice_of_record, invoice_next_seq, invoice_prefix, invoice_pad_width, credit_memo_prefix)
  select p_company_id, 'strata',
         greatest(1, public.max_numeric_invoice_number(p_company_id) + 1),
         '', 6, 'CM-'
   where not exists (select 1 from public.billing_settings where company_id = p_company_id)
  on conflict (company_id) do nothing;

  loop
    v_guard := v_guard + 1;
    if v_guard > 1000 then
      raise exception 'no free invoice number for company % after 1000 attempts (last tried %)',
        p_company_id, v_candidate;
    end if;

    update public.billing_settings
       set invoice_next_seq = invoice_next_seq + 1,
           updated_at       = now()
     where company_id = p_company_id
    returning invoice_next_seq - 1, invoice_prefix, invoice_pad_width, invoice_of_record
         into v_seq, v_prefix, v_pad, v_mode;

    if not found then
      raise exception 'no billing settings for company % and none could be created — check your access', p_company_id;
    end if;
    if v_mode = 'quickbooks' then
      raise exception 'company % has QuickBooks set as its invoice of record — turn that off in Settings to invoice from STRATA', p_company_id;
    end if;

    v_candidate := coalesce(v_prefix, '') || lpad(v_seq::text, coalesce(v_pad, 6), '0');

    -- 🔴 `o.` is load-bearing: unqualified, invoice_number matches this
    -- function's OUT parameter as well as the column (20260910000015).
    exit when not exists (
      select 1 from public.orders o
       where o.company_id = p_company_id
         and o.invoice_number = v_candidate
    );

    if not v_jumped then
      v_jumped := true;
      update public.billing_settings
         set invoice_next_seq = greatest(
               invoice_next_seq,
               public.max_numeric_invoice_number(p_company_id) + 1
             )
       where company_id = p_company_id;
    end if;
  end loop;

  invoice_sequence := v_seq;
  invoice_number   := v_candidate;
  return next;
end;
$function$;

create or replace function public.allocate_credit_memo_number(p_company_id text)
returns table(credit_memo_sequence bigint, credit_memo_number text)
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_seq    bigint;
  v_prefix text;
  v_pad    integer;
  v_mode   text;
begin
  -- Issuing a credit memo (invoice.void) or waiving a late fee
  -- (ar.late_fee_apply) are the two paths that mint one.
  perform public.guard_counter_caller(
    p_company_id, array['invoice.void', 'ar.late_fee_apply', 'billing.configure']);

  insert into public.billing_settings
    (company_id, invoice_of_record, invoice_next_seq, invoice_prefix, invoice_pad_width, credit_memo_prefix)
  select p_company_id, 'strata',
         greatest(1, public.max_numeric_invoice_number(p_company_id) + 1),
         '', 6, 'CM-'
   where not exists (select 1 from public.billing_settings where company_id = p_company_id)
  on conflict (company_id) do nothing;

  update public.billing_settings
     set credit_memo_next_seq = credit_memo_next_seq + 1,
         updated_at           = now()
   where company_id = p_company_id
  returning credit_memo_next_seq - 1, credit_memo_prefix, invoice_pad_width, invoice_of_record
       into v_seq, v_prefix, v_pad, v_mode;

  if not found then
    raise exception 'no billing settings for company % and none could be created — check your access', p_company_id;
  end if;
  if v_mode = 'quickbooks' then
    raise exception 'company % has QuickBooks set as its invoice of record — turn that off in Settings to issue credit memos from STRATA', p_company_id;
  end if;

  credit_memo_sequence := v_seq;
  credit_memo_number   := coalesce(v_prefix, 'CM-') || lpad(v_seq::text, coalesce(v_pad, 6), '0');
  return next;
end;
$function$;

-- ═══ 2. the two-tier delete, in the policy and in the function ════════════
-- "Completed" is the app's own test (roast/actions.ts): a roast_date AND some
-- real content on the row. Anything else is queue maintenance.
create or replace function public.roast_log_is_completed(
  p_roast_date timestamp without time zone,
  p_session_id text, p_recipe_id text, p_charge_weight text, p_roasted_weight numeric
) returns boolean
language sql
immutable
as $$
  select p_roast_date is not null
     and (p_session_id is not null
       or p_recipe_id is not null
       or coalesce(nullif(trim(p_charge_weight), ''), null) is not null
       or p_roasted_weight is not null);
$$;

drop policy if exists roast_log_delete on public.roast_log;
create policy roast_log_delete on public.roast_log
  for delete to authenticated
  using (
    -- Always: you must be able to log a roast here at all.
    company_id in (select public.auth_roast_log_company_ids())
    -- And for a FINISHED roast, the key that names deleting one.
    and (
      not public.roast_log_is_completed(roast_date, session_id, recipe_id, charge_weight, roasted_weight)
      or company_id in (select public.auth_roast_delete_company_ids())
    )
  );

-- delete_roasts restores the green BEFORE the DELETE. If the DELETE is then
-- filtered away by the policy, the inventory credit stands on its own and the
-- roast survives. Refuse at the top instead, with the reason.
create or replace function public.guard_delete_roasts_caller(p_roast_log_ids text[])
returns void
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then return; end if;

  if exists (
    select 1 from public.roast_log rl
     where rl.roast_log_id = any(p_roast_log_ids)
       and not public.auth_has_permission('roast.log', rl.company_id)
  ) then
    raise exception 'You may not delete a roast.' using errcode = 'insufficient_privilege';
  end if;

  if exists (
    select 1 from public.roast_log rl
     where rl.roast_log_id = any(p_roast_log_ids)
       and public.roast_log_is_completed(rl.roast_date, rl.session_id, rl.recipe_id, rl.charge_weight, rl.roasted_weight)
       and not public.auth_has_permission('roast.delete_completed', rl.company_id)
  ) then
    raise exception 'You may not delete a completed roast.' using errcode = 'insufficient_privilege';
  end if;
end;
$$;

revoke all on function public.guard_delete_roasts_caller(text[]) from public, anon;
grant execute on function public.guard_delete_roasts_caller(text[]) to authenticated, service_role;

-- delete_roasts, unchanged except for the guard at the top.
CREATE OR REPLACE FUNCTION public.delete_roasts(p_roast_log_ids text[])
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_o record;
BEGIN
    IF p_roast_log_ids IS NULL OR array_length(p_roast_log_ids, 1) IS NULL THEN
        RETURN;
    END IF;

    -- 🔴 BEFORE the inventory credit below. This function restores green and
    -- only then DELETEs; if the policy filters the DELETE to zero rows the
    -- credit stands alone and the roast survives, which is how 20260910000018's
    -- delete gate turned a refused delete into silent inventory inflation.
    PERFORM public.guard_delete_roasts_caller(p_roast_log_ids);

    CREATE TEMP TABLE _del_cons ON COMMIT DROP AS
    SELECT rlc.origin_purchase_id,
           cip.origin        AS origin,
           rl.facility_id     AS facility_id,
           rl.company_id      AS company_id,
           rlc.lbs_consumed   AS lbs_consumed,
           COALESCE(rl.roast_date_utc,
                    (rl.roast_date AT TIME ZONE COALESCE(NULLIF(f.time_zone, ''), 'UTC'))) AS roast_utc
      FROM public.roast_log_lot_consumption rlc
      JOIN public.coffee_inventory_purchased cip ON cip.origin_purchase_id = rlc.origin_purchase_id
      JOIN public.roast_log rl ON rl.roast_log_id = rlc.roast_log_id
      LEFT JOIN public.facilities f ON f.facility_id = rl.facility_id
     WHERE rlc.roast_log_id = ANY(p_roast_log_ids)
       AND cip.origin IS NOT NULL
       AND rl.facility_id IS NOT NULL;

    CREATE TEMP TABLE _del_origin ON COMMIT DROP AS
    SELECT origin, facility_id,
           MIN(company_id)            AS company_id,
           MIN(roast_utc)             AS min_utc,
           bool_or(roast_utc IS NULL) AS has_null_utc
      FROM _del_cons
     GROUP BY origin, facility_id;

    ALTER TABLE _del_origin ADD COLUMN needs_replay boolean;

    UPDATE _del_origin d
       SET needs_replay = d.has_null_utc OR d.min_utc IS NULL OR EXISTS (
            SELECT 1
              FROM public.roast_log rl2
              LEFT JOIN public.roast_recipes rr2 ON rr2.recipe_id = rl2.recipe_id
              LEFT JOIN public.facilities f2 ON f2.facility_id = rl2.facility_id
             WHERE rl2.facility_id = d.facility_id
               AND rl2."charged?" = true
               AND COALESCE(rl2.charge_weight_lbs, 0) > 0
               AND NOT (rl2.roast_log_id = ANY(p_roast_log_ids))
               AND (rl2.external_roast_id IS NOT NULL
                    OR rl2.roast_date >= (rl2.created_at::date - interval '1 day'))
               AND COALESCE(rl2.roast_date_utc,
                            (rl2.roast_date AT TIME ZONE COALESCE(NULLIF(f2.time_zone, ''), 'UTC'))) >= d.min_utc
               AND (
                    (rl2.borrow_origin_purchase_id IS NULL AND (
                        (rr2.roast_type = 'Pre-Blend'
                           AND (
                             -- native component of the deleted origin
                             EXISTS (SELECT 1 FROM public.recipe_components rc
                                      WHERE rc.recipe_id = rl2.recipe_id
                                        AND rc.coffee_item = d.origin
                                        AND COALESCE(rc.percentage, 0) > 0)
                             -- source-true: a component BORROWED into d.origin
                             -- (its planned source is homed in the deleted origin)
                             OR EXISTS (
                                  SELECT 1
                                    FROM jsonb_each_text(rl2.planned_lots) pl
                                    JOIN public.coffee_source cs ON cs.coffee_source_id = pl.value
                                    JOIN public.recipe_components rc2 ON rc2.recipe_id = rl2.recipe_id
                                                                    AND rc2.coffee_item = pl.key
                                   WHERE jsonb_typeof(rl2.planned_lots) = 'object'
                                     AND cs.origin_id = d.origin
                                     AND cs.origin_id IS DISTINCT FROM pl.key
                                     AND COALESCE(rc2.percentage, 0) > 0)
                           ))
                        OR ((rr2.roast_type IS NULL OR rr2.roast_type <> 'Pre-Blend')
                              AND rl2.origin_id = d.origin)))
                    OR (rl2.borrow_origin_purchase_id IS NOT NULL
                          AND EXISTS (SELECT 1 FROM public.coffee_inventory_purchased b
                                       WHERE b.origin_purchase_id = rl2.borrow_origin_purchase_id
                                         AND b.origin = d.origin))
               )
       )
     WHERE true;  -- update every row; explicit WHERE satisfies pg_safeupdate (REST)

    UPDATE public.coffee_inventory_purchased cip
       SET remaining_lbs = COALESCE(cip.remaining_lbs, 0) + agg.lbs
      FROM (
        SELECT c.origin_purchase_id, SUM(c.lbs_consumed) AS lbs
          FROM _del_cons c
          JOIN _del_origin d ON d.origin = c.origin AND d.facility_id = c.facility_id
         WHERE d.needs_replay = false
         GROUP BY c.origin_purchase_id
      ) agg
     WHERE cip.origin_purchase_id = agg.origin_purchase_id;

    PERFORM set_config('app.defer_lot_recompute', 'true', true);
    DELETE FROM public.roast_log WHERE roast_log_id = ANY(p_roast_log_ids);
    PERFORM set_config('app.defer_lot_recompute', 'false', true);

    FOR v_o IN SELECT origin, facility_id, company_id, needs_replay FROM _del_origin LOOP
        IF v_o.needs_replay THEN
            -- Incremental reversal above already restored this origin's totals;
            -- the exact FIFO re-attribution can go deep — route through the
            -- depth guard (inline when shallow, queued when deep).
            PERFORM public.recompute_or_enqueue(v_o.origin, v_o.facility_id, v_o.company_id, 'mid-history roast delete');
        ELSE
            PERFORM public.recalculate_origin_total_stock(v_o.origin, v_o.facility_id);
        END IF;
        PERFORM public.refresh_coffee_stock_par(v_o.origin, v_o.facility_id);
    END LOOP;
END;
$function$;

commit;
