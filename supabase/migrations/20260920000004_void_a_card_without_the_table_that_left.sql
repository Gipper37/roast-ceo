-- void_bin_card still joins a table that was dropped four migrations later.
--
-- 20260908000025 wrote void_bin_card against the SET model, where a card could
-- name several batches through bin_card_source. 20260908000026 collapsed that
-- to one card, one batch -- roast_log_id moved onto bin_card itself and
-- bin_card_source was dropped -- and this function was not revisited.
--
-- So voiding any bin card fails outright:
--
--     42P01  relation "public.bin_card_source" does not exist
--
-- Confirmed against staging today on demo-bincard-pb-1. plpgsql resolves the
-- relation when the statement first executes, not when the function is
-- created, which is why the migration applied cleanly and nothing noticed for
-- twelve days. The error lands before the UPDATE, so no card was half-voided;
-- the feature has simply never worked since the day after it shipped.
--
-- The join was only ever counting how many bagging runs already cite the
-- batches on this card. One card is one batch now, so that is a single
-- equality against the column the card already carries. No lookup table, and
-- no behaviour change: same number, same meaning, same heads-up in the return.

begin;

create or replace function public.void_bin_card(p_bin_card_id text, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_c     public.bin_card;
  v_actor record;
  v_used  int;
begin
  select * into v_c from public.bin_card
   where bin_card_id = p_bin_card_id
     and company_id in (select auth_company_ids());
  if v_c.bin_card_id is null then
    raise exception 'That card is not one of yours.' using errcode = 'insufficient_privilege';
  end if;
  if not public.auth_has_permission('pack.void', v_c.company_id) then
    raise exception 'You do not have permission to void a bin card.' using errcode = 'insufficient_privilege';
  end if;
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'Say why the card is being withdrawn. A card pulled for no stated reason tells the next person nothing.'
      using errcode = 'invalid_parameter_value';
  end if;
  if v_c.voided_at is not null then
    raise exception 'That card was already voided.' using errcode = 'invalid_parameter_value';
  end if;

  -- Withdrawing the paper does not unwind a bagging run that already cited it.
  -- Report it so the person voiding knows a correction may also be owed.
  --
  -- One card, one batch since 20260908000026, so this reads the card's own
  -- roast_log_id rather than the bin_card_source table that used to fan a
  -- card out across several. A card minted before roast_log_id existed has it
  -- NULL, and counts zero rather than matching every run with a null batch.
  select count(*) into v_used
    from public.pack_run_source ps
   where v_c.roast_log_id is not null
     and ps.roast_log_id = v_c.roast_log_id;

  select * into v_actor from public.actor_at(now());

  update public.bin_card
     set voided_at = now(), voided_by = v_actor.team_member_id, void_reason = trim(p_reason)
   where bin_card_id = p_bin_card_id;

  return jsonb_build_object(
    'voided', true,
    'card_code', v_c.card_code,
    'by', v_actor.actor_name,
    -- Not a failure; a heads-up. Voiding paper cannot un-bag coffee.
    'runs_already_citing_these_batches', v_used);
end;
$$;

comment on function public.void_bin_card(text, text) is
  'Withdraw a bin card that was printed in error. Rides on pack.void, not pack.bin_card: printing one is anybody''s job, saying a piece of paper already in the building is wrong is a supervisor''s. The card is never deleted, because a recall has to see that it existed and was withdrawn.';

revoke all on function public.void_bin_card(text, text) from public;
grant execute on function public.void_bin_card(text, text) to authenticated;

commit;
