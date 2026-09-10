-- A report shows what is inside its dates. Nothing else.
--
-- 20260908000029 windowed only the ADMISSION — the "could not be traced" list —
-- and left the report itself unbounded, so a recall would still print roast
-- batches and green from before the tenant had any traceability at all. Half a
-- window is worse than none: it reads as though everything shown is in scope.
--
-- Two things this adds:
--
-- 1. THE REPORT IS CLIPPED. Roasts outside the window leave v_roasts, and the
--    runs, green, bags and customers that hang off them go with them, because
--    every one of those lists is derived from the roast set. Nothing is shown
--    that the trace does not actually cover.
--
-- 2. THE DATES ARE THE OPERATOR'S. p_from / p_to default to the tenant's
--    traceability start and today, and a person running a recall can narrow
--    them — "everything we shipped in August" is a real question and the report
--    could not answer it. p_from can never precede trace_start_date: widening
--    past the day lot tracking began would print history the system never
--    tracked and imply it was checked.
--
-- The starting point itself is NEVER clipped. If somebody hands back a bag from
-- 2019, the report still names that bag — refusing to show the thing you are
-- holding because it predates the window would be absurd. The window governs
-- what else is drawn in.

begin;

do $mig$
declare v_def text;
begin
  select pg_get_functiondef(oid) into v_def
    from pg_proc where proname = 'recall_report' and pronamespace = 'public'::regnamespace;
  if v_def is null then
    raise exception 'recall_report is missing — refusing to patch nothing.';
  end if;
  if v_def like '%p_from%' then
    raise notice 'recall_report already takes a date range — nothing to do.';
    return;
  end if;

  -- Two more arguments, defaulted so every existing caller is unaffected.
  v_def := replace(v_def,
    'p_scope text DEFAULT ''green''::text)',
    'p_scope text DEFAULT ''green''::text, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)');
  if v_def not like '%p_from date%' then
    raise exception 'Could not add the date range — recall_report has changed shape.';
  end if;

  v_def := replace(v_def,
    '  v_untraceable jsonb := ''[]''::jsonb;',
    '  v_untraceable jsonb := ''[]''::jsonb;' || chr(10) ||
    '  v_from date;' || chr(10) ||
    '  v_to   date;');

  -- Resolve the window, then clip the roast set. Everything else in the report
  -- is derived from v_roasts / v_runs, so clipping here clips all of it.
  v_def := replace(v_def,
    '  select st.trace_start_date into v_trace_from',
    '  -- Clip the trace to its dates. The trigger that fired this recall is' || chr(10) ||
    '  -- exempt: you are holding that bag, whatever its date.' || chr(10) ||
    '  select st.trace_start_date into v_trace_from');

  v_def := replace(v_def,
    '  if v_scope = ''green'' then' || chr(10) ||
    '    select coalesce(jsonb_agg(jsonb_build_object(',
    '  -- p_from may narrow the window but never widen it past the day lot' || chr(10) ||
    '  -- tracking began — that would print history nobody tracked and imply' || chr(10) ||
    '  -- somebody checked it.' || chr(10) ||
    '  v_from := greatest(p_from, v_trace_from);' || chr(10) ||
    '  if v_from is null then v_from := coalesce(p_from, v_trace_from); end if;' || chr(10) ||
    '  v_to := coalesce(p_to, current_date);' || chr(10) ||
    '' || chr(10) ||
    '  if v_from is not null or p_to is not null then' || chr(10) ||
    '    select coalesce(array_agg(rl.roast_log_id), ''{}'')' || chr(10) ||
    '      into v_roasts' || chr(10) ||
    '      from public.roast_log rl' || chr(10) ||
    '     where rl.roast_log_id = any (coalesce(v_roasts, ''{}''))' || chr(10) ||
    '       and (v_from is null or rl.roast_date::date >= v_from)' || chr(10) ||
    '       and (v_to   is null or rl.roast_date::date <= v_to);' || chr(10) ||
    '' || chr(10) ||
    '    select coalesce(array_agg(pr.pack_run_id), ''{}'')' || chr(10) ||
    '      into v_runs' || chr(10) ||
    '      from public.pack_run pr' || chr(10) ||
    '     where pr.pack_run_id = any (coalesce(v_runs, ''{}''))' || chr(10) ||
    '       and (' || chr(10) ||
    '         -- the bag that came back is never clipped out of its own recall' || chr(10) ||
    '         (p_lot_code is not null and pr.lot_code = p_lot_code)' || chr(10) ||
    '         or ((v_from is null or pr.packed_on >= v_from)' || chr(10) ||
    '             and (v_to is null or pr.packed_on <= v_to)));' || chr(10) ||
    '  end if;' || chr(10) ||
    '' || chr(10) ||
    '  if v_scope = ''green'' then' || chr(10) ||
    '    select coalesce(jsonb_agg(jsonb_build_object(');

  -- The untraceable list already honoured trace_start_date; make it honour the
  -- operator's narrower range too, so the admission matches the report.
  v_def := replace(v_def,
    '       and (v_trace_from is null or rl.roast_date::date >= v_trace_from)',
    '       and (v_from is null or rl.roast_date::date >= v_from)' || chr(10) ||
    '       and (v_to   is null or rl.roast_date::date <= v_to)');

  -- Say which dates the report actually covers, so nobody has to infer it.
  v_def := replace(v_def,
    '    ''trace_start_date'', v_trace_from,',
    '    ''trace_start_date'', v_trace_from,' || chr(10) ||
    '    ''covers_from'', v_from,' || chr(10) ||
    '    ''covers_to'', v_to,');

  execute v_def;
end
$mig$;

revoke all on function public.recall_report(text, text, text, text, date, date) from public;
grant execute on function public.recall_report(text, text, text, text, date, date) to authenticated;

commit;
