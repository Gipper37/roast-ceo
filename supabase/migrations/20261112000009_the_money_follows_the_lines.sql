-- The money follows the lines.
--
-- Owner: "an order is editable until it is delivered or invoice sent." The
-- guards were re-meant for that in 20261112000003 and 20261112000005. The
-- three functions that compute an order's money were not, and they still
-- refuse on `posted` -- which is true the moment a number is issued, and a
-- number is issued at the bench while the order is still being packed.
--
-- 🔴 SO ON EXACTLY THE WORKFLOW THIS BATCH EXISTS TO ENABLE -- print at the
-- bench, then fix a line before the van goes -- order_total followed the
-- lines (update_order_aggregates has no such guard) while discount_total, the
-- per-line discount_amount and tax_amount did not, and no path existed to
-- recompute them. The invoice the customer is handed then shows a discount
-- percentage that is not the discount taken, and tax charged on a total that
-- no longer exists. 69 prod orders carry an order-level discount; 4,034 carry
-- tax. Nothing repairs it afterwards, because the same guard refuses the
-- repair.
--
-- `posted` is replaced by order_figures_are_final, not by
-- order_document_is_closed. The difference is the whole point and getting it
-- wrong breaks finalize_invoice: a delivered, never-billed order is CLOSED,
-- and finalize_invoice's last act before minting its number is to resolve its
-- tax. Final means the customer has actually been shown the figure.
--
-- 🔴 NEITHER BODY IS RETYPED. CREATE OR REPLACE rewrites all of a function,
-- and recompute_order_tax is a page of rate-resolution nobody should retype
-- to change one predicate. Each body is read out, its guard replaced at an
-- anchor asserted to occur exactly once, and written back with its own
-- attributes preserved.

begin;

do $$
declare
  v_src text; v_new text; v_hits integer; v_secdef boolean; v_cfg text; v_args text;
  r record;
begin
  for r in
    select * from (values
      ('recompute_order_tax',
       '  if v_o.posted or v_o.legacy then' || chr(10) ||
       '    raise exception ''order % is posted or imported history — its tax is locked'', p_order_id;' || chr(10) ||
       '  end if;',
       '  if public.order_figures_are_final(p_order_id) or v_o.legacy then' || chr(10) ||
       '    raise exception ''order % has been sent to the customer — its tax is locked'', p_order_id;' || chr(10) ||
       '  end if;'),
      ('apply_order_discount',
       '  if exists (select 1 from public.orders' || chr(10) ||
       '              where order_id = p_order_id' || chr(10) ||
       '                and (coalesce(posted,false) or coalesce(is_legacy_import,false))) then',
       '  if public.order_figures_are_final(p_order_id)' || chr(10) ||
       '     or exists (select 1 from public.orders' || chr(10) ||
       '                 where order_id = p_order_id and coalesce(is_legacy_import,false)) then')
    ) as t(fn, anchor, repl)
  loop
    select p.prosrc, p.prosecdef, coalesce(array_to_string(p.proconfig, ''', '''), ''),
           pg_get_function_identity_arguments(p.oid)
      into v_src, v_secdef, v_cfg, v_args
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = r.fn;

    if v_src is null then
      raise exception '%() is gone, so the money cannot be made to follow the lines', r.fn;
    end if;

    if position('order_figures_are_final' in v_src) > 0 then
      raise notice '%() already asks whether the figures are final; left alone', r.fn;
      continue;
    end if;

    select count(*) into v_hits from regexp_matches(v_src, regexp_replace(r.anchor, '([.^$*+?()\[\]{}|\\])', '\\\1', 'g'), 'g');
    if v_hits <> 1 then
      raise exception '%() has % copies of its guard anchor, not 1 — refusing to edit it blind', r.fn, v_hits;
    end if;

    v_new := replace(v_src, r.anchor, r.repl);

    execute format('create or replace function public.%I(%s) returns %s language plpgsql %s %s as %L',
      r.fn, v_args,
      (select pg_get_function_result(p.oid) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname='public' and p.proname = r.fn),
      case when v_secdef then 'security definer' else '' end,
      case when v_cfg <> '' then format('set search_path to %s', quote_literal(split_part(v_cfg,'=',2))) else '' end,
      v_new);
    raise notice '%() now asks whether the figures are final', r.fn;
  end loop;
end $$;

-- ── Prove it ───────────────────────────────────────────────────────────
do $$
declare v_fn text;
begin
  foreach v_fn in array array['recompute_order_tax', 'apply_order_discount'] loop
    if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'public' and p.proname = v_fn
                      and p.prosrc like '%order_figures_are_final%') then
      raise exception '%() still refuses on posted, so a bench-printed order''s money cannot follow its lines', v_fn;
    end if;
  end loop;

  -- The bodies survived the edit: each still contains the work it does, not
  -- just the guard that was swapped.
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'recompute_order_tax'
                    and p.prosrc like '%resolve_tax_rate%') then
    raise exception 'recompute_order_tax lost its body';
  end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'apply_order_discount'
                    and p.prosrc like '%order_allocated%') then
    raise exception 'apply_order_discount lost its body';
  end if;
end $$;

-- 🔴 THE COMMENT IS THE RECORD, AND CREATE OR REPLACE KEEPS THE OLD ONE.
-- Same oid, so both of these still ended "Refuses on a posted invoice." --
-- which this migration has just made false. Anyone reading \df+ or a schema
-- dump to decide whether a bench-printed order may take a discount would get
-- the pre-batch answer from the database itself.
comment on function public.recompute_order_tax(text) is
  'Resolves an order''s tax the way finalize_invoice resolves it at the moment of numbering. Refuses once the customer has been shown the figures -- see order_figures_are_final -- NOT merely once the invoice has been printed: a delivered order nobody has billed must still be able to resolve its tax, or it is numbered and issued untaxed.';

comment on function public.apply_order_discount(text, text, numeric) is
  'Applies an order-level discount and re-derives every number the invoice shows. Refuses once the customer has been shown the figures -- see order_figures_are_final -- NOT merely once the invoice has been printed: the warehouse prints the invoice before the van loads, and that print must not freeze the order.';

commit;
