-- Recalls are admins only, and sending has to be said twice.
--
-- Owner, 2026-09-07: "recalls should be admin only. there's should be explicit
-- double confirmation before sending emails/notices btw"
--
-- 1. `recall.manage` was granted to manager as well as the two admin roles. It
--    should not be. Starting a recall commits the company to a position, and
--    sending the notice mails every affected customer in the roaster's name.
--    That is an owner's decision, not a shift decision.
--
-- 2. The second confirmation is enforced HERE, not only in a dialog. A modal is
--    a suggestion; the send RPC is reachable directly. So the caller has to name
--    the recall AND state how many people they are about to mail, and the number
--    has to match what is actually pending. That makes the confirmation real,
--    and it catches the more likely accident: somebody reviews a list of four,
--    leaves the screen open while a colleague adds a customer, and comes back to
--    press send on a list that is now five.

begin;

delete from public.role_permissions
 where permission_id = 'recall.manage' and role_id = 'manager';

comment on column public.recall.status is
  'draft while it is being built and reviewed · notified once the notices have gone · closed when the recall is finished. Only an admin can move it.';

-- ── The send guard ──────────────────────────────────────────────────────────
-- Returns the notices that are about to go, and refuses unless the caller's
-- count matches. Deliberately NOT the thing that sends: the app sends the mail,
-- because that is where the templates and the roaster identity live. This is the
-- gate in front of it.
create or replace function public.confirm_recall_send(
  p_recall_id       text,
  p_expected_count  int
)
returns setof public.recall_notice
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_company text;
  v_actual  int;
  v_status  text;
begin
  select company_id, status into v_company, v_status
    from public.recall where recall_id = p_recall_id
      and company_id in (select auth_company_ids());
  if v_company is null then
    raise exception 'No such recall.' using errcode = 'no_data_found';
  end if;
  if not public.auth_has_permission('recall.manage', v_company) then
    raise exception 'Only an admin can send a recall notice.' using errcode = 'insufficient_privilege';
  end if;
  if v_status = 'closed' then
    raise exception 'That recall is closed. Reopen it before sending anything.'
      using errcode = 'invalid_parameter_value';
  end if;

  select count(*) into v_actual
    from public.recall_notice
   where recall_id = p_recall_id and status = 'pending' and nullif(email,'') is not null;

  if v_actual = 0 then
    raise exception 'Nobody on this recall has an email address yet. Add addresses, or mark those customers as reached another way.'
      using errcode = 'invalid_parameter_value';
  end if;

  -- The second confirmation, and the stale-screen guard in one.
  if p_expected_count is distinct from v_actual then
    raise exception 'This would email % customer(s), not %. The list changed since you reviewed it — check it again.',
      v_actual, p_expected_count
      using errcode = 'invalid_parameter_value';
  end if;

  return query
    select * from public.recall_notice
     where recall_id = p_recall_id and status = 'pending' and nullif(email,'') is not null;
end;
$$;

comment on function public.confirm_recall_send(text, int) is
  'The second confirmation, enforced where a dialog cannot be skipped: name the recall and state how many people you are mailing. A mismatch means the list moved since you looked at it.';

revoke all on function public.confirm_recall_send(text, int) from public;
grant execute on function public.confirm_recall_send(text, int) to authenticated;

commit;
