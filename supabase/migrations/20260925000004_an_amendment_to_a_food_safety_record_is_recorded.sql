-- The one shipped edit that rewrote a food-safety record in silence.
--
-- pack_run_correction was built as an append-only amendment log because "an
-- edit that silently overwrites a food-safety record is the falsification
-- Costco 5.1.11 is about" (20260908000007). It has never received a row. Its
-- only writer, correct_pack_run, has no caller in the app.
--
-- Meanwhile set_pack_run_best_before DOES have callers — the label screen's
-- "Save it on the record" button AND the print button itself, which calls it
-- on the way to window.print(). So the one edit a packer can actually make to
-- a closed bagging record is the one that wrote no amendment row, had no
-- voided-run guard, and additionally moved the company-wide
-- fs_settings.shelf_life_days default.
--
-- Three changes, all inside the function, body taken from pg_get_functiondef:
--   * it logs the amendment, with the PIN'd terminal actor where there is one
--     and the logged-in member otherwise
--   * it refuses a voided run, as correct_pack_run already does
--   * it only logs when the date actually changes, so printing twice does not
--     manufacture a paper trail
--
-- And two things around it, because a locked front door in a wall with a hole
-- is not a control:
--   * authenticated loses UPDATE and DELETE on pack_run. Every legitimate
--     write goes through open/close/correct/void/set_best_before, all SECURITY
--     DEFINER, so they are unaffected; what stops is a bagger rewriting a
--     closed record — count, best-before, even the printed lot code — with one
--     PATCH to /rest/v1/pack_run.
--   * the two child foreign keys stop cascading. pack_run_correction and
--     pack_run_source were ON DELETE CASCADE, so deleting a pack run erased
--     its own amendment log and its roast trace along with it. A falsification
--     control that the falsifier can delete is not one.
--
-- Zero pack_run rows exist on prod, so none of this disturbs live data.

begin;

CREATE OR REPLACE FUNCTION public.set_pack_run_best_before(p_pack_run_id text, p_best_before date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_company text; v_packed date; v_roasted date; v_days int;
        v_old date; v_voided timestamptz; v_actor text; v_actor_name text;
begin
  select pr.company_id, pr.packed_on,
         (select max(rl.roast_date)::date
            from public.pack_run_source s
            join public.roast_log rl on rl.roast_log_id = s.roast_log_id
           where s.pack_run_id = pr.pack_run_id),
         pr.best_before, pr.voided_at
    into v_company, v_packed, v_roasted, v_old, v_voided
    from public.pack_run pr
   where pr.pack_run_id = p_pack_run_id and pr.company_id in (select auth_company_ids());
  if v_company is null then raise exception 'No such pack run.' using errcode = 'no_data_found'; end if;
  if not public.auth_has_permission('pack.run', v_company) then
    raise exception 'You do not have permission to change this.' using errcode = 'insufficient_privilege';
  end if;
  -- A voided run is a closed record. correct_pack_run refuses one; this did not,
  -- so the label screen could still move a voided lot's date.
  if v_voided is not null then
    raise exception 'That pack run was voided. Its record cannot be changed.'
      using errcode = 'invalid_parameter_value';
  end if;
  if p_best_before is not null and p_best_before < v_packed then
    raise exception 'A best-before date cannot fall before the day the coffee was bagged.'
      using errcode = 'invalid_parameter_value';
  end if;

  update public.pack_run
     set best_before = p_best_before, updated_at = now()
   where pack_run_id = p_pack_run_id;

  -- 🔴 THE AMENDMENT. This function is reached from the LABEL screen, and the
  -- print button itself calls it — so a best-before printed on bags already in
  -- a customer's cafe could be rewritten with nothing recording that it had
  -- ever said anything else. pack_run_correction exists precisely to stop that
  -- (Costco 5.1.11, falsification, an automatic-failure critical) and this was
  -- the one shipped path that wrote to a closed record without using it.
  if p_best_before is distinct from v_old then
    select ses.team_member_id, pinned.name
      into v_actor, v_actor_name
      from public.terminal_actor_session ses
      join public.team pinned on pinned.team_member_id = ses.team_member_id
     where ses.ended_at is null and ses.expires_at > now()
       and ses.terminal_member_id = (select t.team_member_id from public.team t
                                      where t.auth_user_id = auth.uid() limit 1)
     limit 1;
    if v_actor is null then
      select t.team_member_id, t.name into v_actor, v_actor_name
        from public.team t where t.auth_user_id = auth.uid() limit 1;
    end if;

    insert into public.pack_run_correction
      (pack_run_id, company_id, field, old_value, new_value, reason,
       corrected_by, corrected_by_name)
    values (p_pack_run_id, v_company, 'best_before',
            v_old::text, p_best_before::text,
            'Changed on the label screen',
            v_actor, v_actor_name);
  end if;

  -- Remember it, when it is a sane shelf life measured from the roast.
  if p_best_before is not null and coalesce(v_roasted, v_packed) is not null then
    v_days := p_best_before - coalesce(v_roasted, v_packed);
    if v_days between 1 and 3650 then
      insert into public.fs_settings (company_id, shelf_life_days)
      values (v_company, v_days)
      on conflict (company_id) do update
        set shelf_life_days = excluded.shelf_life_days, updated_at = now();
    else
      v_days := null;
    end if;
  end if;

  return jsonb_build_object('best_before', p_best_before, 'shelf_life_days', v_days);
end;
$function$;


revoke update, delete, truncate on public.pack_run from authenticated, anon;

alter table public.pack_run_correction
  drop constraint if exists pack_run_correction_pack_run_id_fkey;
alter table public.pack_run_correction
  add constraint pack_run_correction_pack_run_id_fkey
  foreign key (pack_run_id) references public.pack_run(pack_run_id) on delete restrict;

alter table public.pack_run_source
  drop constraint if exists pack_run_source_pack_run_id_fkey;
alter table public.pack_run_source
  add constraint pack_run_source_pack_run_id_fkey
  foreign key (pack_run_id) references public.pack_run(pack_run_id) on delete restrict;

do $verify$
declare v_bad int;
begin
  if has_table_privilege('authenticated','public.pack_run','UPDATE')
     or has_table_privilege('authenticated','public.pack_run','DELETE') then
    raise exception 'a packer can still rewrite a closed bagging record directly';
  end if;
  if not has_table_privilege('authenticated','public.pack_run','SELECT') then
    raise exception 'the pack run list can no longer read its own table';
  end if;

  select count(*) into v_bad from pg_constraint
   where conname in ('pack_run_correction_pack_run_id_fkey','pack_run_source_pack_run_id_fkey')
     and confdeltype <> 'r';
  if v_bad > 0 then raise exception '% child key(s) still cascade the audit trail away', v_bad; end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname='public' and p.proname='set_pack_run_best_before'
       and pg_get_functiondef(p.oid) like '%pack_run_correction%')
  then
    raise exception 'set_pack_run_best_before still rewrites the record without logging it';
  end if;

  raise notice 'a pack run can be amended only through a function, and every amendment is recorded';
end $verify$;

commit;
