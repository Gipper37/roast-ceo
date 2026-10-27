-- Drop the pre-device overloads.
--
-- 000024 added `p_device_id` to terminal_pin_in and terminal_pin_out with
-- CREATE OR REPLACE. Adding a parameter does not REPLACE a function, it
-- OVERLOADS it, so production now carries both:
--
--     terminal_pin_in  (text, text, text)         <- pre-device
--     terminal_pin_in  (text, text, text, text)
--     terminal_pin_out (text)                     <- pre-device
--     terminal_pin_out (text, text)
--
-- 🔴 THE OLD ONES ARE NOT HARMLESS. terminal_pin_in(text,text,text) clears
-- EVERY open row for the account, which is precisely the behaviour that locked
-- the roasting terminal out when somebody PIN'd in at the bagging one. And
-- PostgREST resolves by the argument names a caller sends, so any caller that
-- omits p_device_id silently gets the pre-device behaviour back.
--
-- 🔴 I WROTE THIS WARNING MYSELF, IN 000018, ABOUT THE SAME TWO FUNCTIONS:
-- "A parameter TYPE cannot be changed by CREATE OR REPLACE -- that creates an
-- OVERLOAD and leaves the broken one in place, which PostgREST could still
-- resolve. Each must be dropped and recreated." That migration asserted the
-- stale overloads were gone. 000024 added parameters instead of changing
-- types, did not make the same assertion, and reintroduced the same hazard six
-- migrations later.

begin;

drop function if exists public.terminal_pin_in(text, text, text);
drop function if exists public.terminal_pin_out(text);

do $$
declare v_n int;
begin
  if to_regprocedure('public.terminal_pin_in(text, text, text)') is not null then
    raise exception 'the pre-device terminal_pin_in overload still exists';
  end if;
  if to_regprocedure('public.terminal_pin_out(text)') is not null then
    raise exception 'the pre-device terminal_pin_out overload still exists';
  end if;
  if to_regprocedure('public.terminal_pin_in(text, text, text, text)') is null then
    raise exception 'the device-aware terminal_pin_in is missing';
  end if;
  if to_regprocedure('public.terminal_pin_out(text, text)') is null then
    raise exception 'the device-aware terminal_pin_out is missing';
  end if;

  -- Exactly one of each, so no third form can be resolved by accident.
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'terminal_pin_in';
  if v_n <> 1 then raise exception 'terminal_pin_in has % overloads, expected 1', v_n; end if;

  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'terminal_pin_out';
  if v_n <> 1 then raise exception 'terminal_pin_out has % overloads, expected 1', v_n; end if;

  if not has_function_privilege('authenticated', 'public.terminal_pin_in(text, text, text, text)', 'execute')
     or not has_function_privilege('authenticated', 'public.terminal_pin_out(text, text)', 'execute') then
    raise exception 'authenticated cannot execute the device-aware pin functions';
  end if;

  raise notice 'one terminal_pin_in and one terminal_pin_out, both device aware';
end $$;

commit;
