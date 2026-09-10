-- A recall must not report silence as safety.
--
-- Two faults, and they have to be fixed together or the fix makes things worse.
--
-- ── 1. An untraceable roast is INVISIBLE, not flagged ─────────────────────
-- A green-scope recall builds its roast list by joining
-- roast_log_lot_consumption to the suspect lot. A roast with NO consumption row
-- has no edge to any green, so it never enters that list, its pack runs never
-- enter the run list, and its bags are never named. coalesce(...,'[]') then
-- turns the empty result into an empty array and the report reads as "nothing
-- else is affected" — which is the one sentence a recall must never say by
-- accident. Prod carries roasts in exactly that state.
--
-- ── 2. …but a tenant's pre-implementation history is not a finding ────────
-- Maui Coffee Roasters has 445 roasts with unattributed green from before any
-- of this existed — the years the system was bought to end. Surfacing fault 1
-- without a window would bury every real answer under that history on day one.
-- Owner: *"the recall needs a window. because for a user implementing (MCR)
-- they don't want all the old shit that didn't get recorded to show up on the
-- report negatively."*
--
-- So: the report now names what it could not trace, and counts only what falls
-- inside fs_settings.trace_start_date. The trace itself is unchanged — every
-- scope still reaches exactly as far as it did. This adds an admission, not a
-- filter on the answer.
--
-- ── 3. And something has to SET the date ──────────────────────────────────
-- trace_start_date existed and defaulted to NULL, which means "report
-- everything" — the bad outcome, reached by nobody doing anything. Switching
-- the food-safety module on IS the cutover event, so that is where it is
-- stamped. In the DATABASE rather than the server action, because the action's
-- own comment says the goal is that "a direct API call gets the same answer as
-- the switch".

begin;

-- ── Stamp the cutover when the module goes on ─────────────────────────────
create or replace function public.stamp_trace_start_on_module_enable()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.feature_key <> 'haccp' or not coalesce(new.enabled, false) then
    return null;
  end if;

  -- Only ever fills a blank. A tenant who set their own date, or who switches
  -- the module off and on again, keeps the date they already have — re-stamping
  -- would silently narrow their trace and hide roasts that used to be in scope.
  insert into public.fs_settings (company_id, trace_start_date)
  values (new.company_id, current_date)
  on conflict (company_id) do update
    set trace_start_date = coalesce(public.fs_settings.trace_start_date, current_date);

  return null;
end;
$$;

drop trigger if exists trg_stamp_trace_start on public.company_feature;
create trigger trg_stamp_trace_start
  after insert or update of enabled on public.company_feature
  for each row execute function public.stamp_trace_start_on_module_enable();

comment on function public.stamp_trace_start_on_module_enable() is
  'Switching the food-safety module on sets where this tenant''s lot traceability begins, if they have not set it themselves. Fills a blank only — never narrows an existing window.';

-- ── Teach recall_report to admit what it could not trace ──────────────────
-- The body is patched programmatically rather than retyped: it is ~200 lines
-- with four doors and every scope's arithmetic in it, and a hand-copy would
-- only guarantee that it LOOKED right. Same technique the released-allocation
-- flag used.
do $mig$
declare
  v_def text;
begin
  select pg_get_functiondef(oid) into v_def
    from pg_proc where proname = 'recall_report' and pronamespace = 'public'::regnamespace;
  if v_def is null then
    raise exception 'recall_report is missing — refusing to patch nothing.';
  end if;
  if v_def like '%untraceable_roasts%' then
    raise notice 'recall_report already carries untraceable_roasts — nothing to do.';
    return;
  end if;

  -- Declare the two new locals alongside the existing ones.
  v_def := replace(v_def,
    '  v_scope   text := coalesce(p_scope, ''green'');',
    '  v_scope   text := coalesce(p_scope, ''green'');' || chr(10) ||
    '  v_trace_from date;' || chr(10) ||
    '  v_untraceable jsonb := ''[]''::jsonb;');
  if v_def not like '%v_untraceable jsonb%' then
    raise exception 'Could not declare the new locals — recall_report has changed shape.';
  end if;

  -- Just before the report is assembled, work out what we could NOT reach.
  -- Only meaningful on a green-scoped recall: it is the scope that claims to
  -- have found everything made from a coffee.
  v_def := replace(v_def,
    '  with roasts as (',
    '  select st.trace_start_date into v_trace_from' || chr(10) ||
    '    from public.fs_settings st where st.company_id = v_company;' || chr(10) ||
    '' || chr(10) ||
    '  if v_scope = ''green'' then' || chr(10) ||
    '    select coalesce(jsonb_agg(jsonb_build_object(' || chr(10) ||
    '             ''roast_log_id'', sf.roast_log_id,' || chr(10) ||
    '             ''roast_date'', rl.roast_date,' || chr(10) ||
    '             ''recipe'', coalesce(rl.recipe_name_snapshot, rr.recipe_name),' || chr(10) ||
    '             ''coffee'', ci2.origin,' || chr(10) ||
    '             ''lbs_unaccounted'', sf.lbs_unmet) order by rl.roast_date desc), ''[]''::jsonb)' || chr(10) ||
    '      into v_untraceable' || chr(10) ||
    '      from public.roast_lot_shortfall sf' || chr(10) ||
    '      join public.roast_log rl on rl.roast_log_id = sf.roast_log_id' || chr(10) ||
    '      left join public.roast_recipes rr on rr.recipe_id = rl.recipe_id' || chr(10) ||
    '      left join public.coffee_inventory ci2' || chr(10) ||
    '             on ci2.origin_id = sf.origin_id and ci2.facility_id = sf.facility_id' || chr(10) ||
    '     where sf.company_id = v_company' || chr(10) ||
    '       and sf.waived_at is null' || chr(10) ||
    '       -- Pre-implementation history is out of scope, not an open question.' || chr(10) ||
    '       and (v_trace_from is null or rl.roast_date::date >= v_trace_from)' || chr(10) ||
    '       -- Only green this recall actually implicates.' || chr(10) ||
    '       and exists (select 1 from public.coffee_inventory_purchased cip2' || chr(10) ||
    '                    where cip2.origin_purchase_id = any (v_green)' || chr(10) ||
    '                      and cip2.origin = sf.origin_id' || chr(10) ||
    '                      and cip2.facility_id = sf.facility_id)' || chr(10) ||
    '       -- Already traced by the normal path: not a gap.' || chr(10) ||
    '       and not (sf.roast_log_id = any (coalesce(v_roasts, ''{}'')));' || chr(10) ||
    '  end if;' || chr(10) ||
    '' || chr(10) ||
    '  with roasts as (');

  -- And say it in the report, beside the totals rather than buried.
  v_def := replace(v_def,
    '    ''totals'', jsonb_build_object(',
    '    ''trace_start_date'', v_trace_from,' || chr(10) ||
    '    -- Roasts this recall KNOWS it could not follow. An empty green trace' || chr(10) ||
    '    -- with a non-empty list here means "we could not trace N roasts", not' || chr(10) ||
    '    -- "nothing else is affected".' || chr(10) ||
    '    ''untraceable_roasts'', v_untraceable,' || chr(10) ||
    '' || chr(10) ||
    '    ''totals'', jsonb_build_object(');

  v_def := replace(v_def,
    '      ''customers'',     (select count(distinct cust) from allocs where cust is not null))',
    '      ''customers'',     (select count(distinct cust) from allocs where cust is not null),' || chr(10) ||
    '      ''untraceable_roasts'', jsonb_array_length(v_untraceable),' || chr(10) ||
    '      ''lbs_unaccounted'', (select coalesce(sum((e->>''lbs_unaccounted'')::numeric), 0)' || chr(10) ||
    '                              from jsonb_array_elements(v_untraceable) e))');

  execute v_def;
end
$mig$;

commit;
