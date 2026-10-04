#!/usr/bin/env bash
#
# module-install-test.sh - is a module actually INSTALLED, or only migrated?
#
# Every failure this checks for has happened in this project, and every one of
# them is SILENT. A permission that is denied because nobody wired its plan rows
# looks exactly like a permission the user is not supposed to have. A table whose
# policy checks tenancy but not the permission looks exactly like a table that is
# protected. A feature_catalog row published before its attachment looks exactly
# like a working switch.
#
# So this is not a unit test and it does not replace one. It asks a database
# whether the wiring a module needs is actually there, and it is meant to run
# against staging before a release and against prod after one.
#
#   ./scripts/module-install-test.sh                      # prod (default)
#   ./scripts/module-install-test.sh --db "postgres://..." # anywhere
#
# Exit 0 = every check passed. Exit 1 = at least one FAIL.
#
# ── What it checks, and the incident behind each ───────────────────────────
#
# 1. A key the frontend names must EXIST.
#    An unknown permission key resolves to DENIED with no error anywhere, so a
#    whole feature is simply dark. 20261003000010 shipped the customer_chain
#    table and forgot customer.chain_manage entirely; the UI built on it would
#    have been dead on arrival.
#
# 2. A key must have BOTH role rows and plan rows.
#    lib/permissions/server.ts ands planOk with the role grant, and a plan-gated
#    key with no plan_permissions rows is denied on every plan. This is the
#    "a key and its policy must admit the same roles" failure in its plan form.
#
# 3. A module's catalog row must not be published before its attachment.
#    feature_catalog.is_active DEFAULTS TO TRUE and the configuration page
#    renders every active row as a live toggle, so a row with no permissions
#    attached is a switch that controls nothing: a company_admin turns payments
#    off and every card path keeps working.
#
# 4. A module's own tables must be gated by the module's PERMISSION, not only by
#    tenancy. customer_chain shipped as `for all to authenticated` with full
#    grants, so any tenant member could create, rename or delete a chain through
#    PostgREST whatever their role. Same class as the live team-row hole.
#
# 5. A constraint must admit every value the code writes.
#    20261003000011 widens two status CHECKs to accept 'returned'; the webhook
#    writes that word. Shipping the writer without the constraint means every
#    ACH return fails its write, and AP drops the delivery after ~75 attempts.
#
set -uo pipefail

PROD_DB="postgresql://postgres@db.pwpslalerytymorcodlv.supabase.co:5432/postgres"
DB="$PROD_DB"
PGPW="${PGPASSWORD:-SDH-h3FNHXSrxj-}"
PSQL_BIN="${PSQL_BIN:-/opt/homebrew/Cellar/postgresql@17/17.8/bin/psql}"
FRONTEND="${FRONTEND:-$HOME/stratos}"

while [ $# -gt 0 ]; do
  case "$1" in
    --db) DB="$2"; shift 2 ;;
    --frontend) FRONTEND="$2"; shift 2 ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

q() { PGPASSWORD="$PGPW" "$PSQL_BIN" "$DB" -X -q -t -A -F'|' -c "$1" 2>&1; }

FAILS=0
pass() { printf '  \033[32mok\033[0m    %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAILS=$((FAILS+1)); }
warn() { printf '  \033[33mwarn\033[0m  %s\n' "$1"; }
head2() { printf '\n\033[1m%s\033[0m\n' "$1"; }

echo "module-install-test against ${DB%%\?*}"
echo "frontend: $FRONTEND"

# ── 1. Every permission key the frontend names exists in the database ────────
#
# The frontend names a key as a bare string in currentUserCan() and
# requirePermission(). A key that is not in `permissions` is denied silently, so
# this compares the two sides rather than trusting either.
head2 "1. Keys the frontend names must exist"
if [ -d "$FRONTEND" ]; then
  NAMED=$(grep -rhoE "(currentUserCan|requirePermission|hasPermission)\(\s*'[a-z][a-z0-9_.]*'" \
            "$FRONTEND/app" "$FRONTEND/lib" "$FRONTEND/components" 2>/dev/null \
          | grep -oE "'[a-z][a-z0-9_.]*'" | tr -d "'" | sort -u)
  if [ -z "$NAMED" ]; then
    warn "found no permission keys in the frontend; check FRONTEND=$FRONTEND"
  else
    N_NAMED=$(printf '%s\n' "$NAMED" | wc -l | tr -d ' ')
    EXISTING=$(q "select permission_id from permissions order by 1")
    MISSING=""
    while IFS= read -r k; do
      [ -z "$k" ] && continue
      printf '%s\n' "$EXISTING" | grep -qxF "$k" || MISSING="$MISSING $k"
    done <<< "$NAMED"
    if [ -n "$MISSING" ]; then
      for k in $MISSING; do fail "frontend names '$k' and it is NOT in permissions (silently denied)"; done
    else
      pass "all $N_NAMED keys named in the frontend exist"
    fi
  fi
else
  warn "frontend not found at $FRONTEND; skipping the code-vs-database check"
fi

# ── 2. Role rows and plan rows, both ────────────────────────────────────────
head2 "2. Every key is wired to roles AND plans"
NO_ROLES=$(q "
  select p.permission_id from permissions p
   where not exists (select 1 from role_permissions r where r.permission_id = p.permission_id)
   order by 1")
if [ -n "$NO_ROLES" ]; then
  while IFS= read -r k; do [ -n "$k" ] && fail "'$k' has NO role_permissions rows: no role can ever hold it"; done <<< "$NO_ROLES"
else
  pass "every key has at least one role row"
fi

NO_PLANS=$(q "
  select p.permission_id from permissions p
   where p.is_plan_gated
     and not exists (select 1 from plan_permissions pl where pl.permission_id = p.permission_id)
   order by 1")
if [ -n "$NO_PLANS" ]; then
  while IFS= read -r k; do [ -n "$k" ] && fail "'$k' is plan-gated with NO plan_permissions rows: denied on every plan"; done <<< "$NO_PLANS"
else
  pass "every plan-gated key has plan rows"
fi

GRANTED_NO_PLAN=$(q "
  select distinct r.permission_id
    from role_permissions r
    join permissions p on p.permission_id = r.permission_id
   where r.granted and p.is_plan_gated
     and not exists (select 1 from plan_permissions pl
                      where pl.permission_id = p.permission_id and pl.granted)
   order by 1")
if [ -n "$GRANTED_NO_PLAN" ]; then
  while IFS= read -r k; do [ -n "$k" ] && fail "'$k' is granted to a role but no plan grants it: silently dead"; done <<< "$GRANTED_NO_PLAN"
else
  pass "no key is granted to a role while every plan denies it"
fi

# ── 3. A catalog row must not be published before its attachment ────────────
head2 "3. No module switch that controls nothing"
ORPHAN_ACTIVE=$(q "
  select f.feature_key
    from feature_catalog f
   where coalesce(f.is_active, true)
     and not exists (select 1 from permissions p where p.feature_key = f.feature_key)
   order by 1")
if [ -n "$ORPHAN_ACTIVE" ]; then
  while IFS= read -r k; do [ -n "$k" ] && fail "feature_catalog '$k' is_active with NO permission attached: a toggle that does nothing"; done <<< "$ORPHAN_ACTIVE"
else
  pass "every active module has at least one permission attached"
fi

# The inverse: a key attached to a module nobody can enable.
ATTACHED_INACTIVE=$(q "
  select distinct p.permission_id || ' -> ' || p.feature_key
    from permissions p join feature_catalog f on f.feature_key = p.feature_key
   where f.is_active = false
   order by 1")
if [ -n "$ATTACHED_INACTIVE" ]; then
  while IFS= read -r k; do [ -n "$k" ] && fail "$k: the key is gated on a module whose catalog row is inactive, so it is denied for everyone"; done <<< "$ATTACHED_INACTIVE"
else
  pass "no key is gated on an inactive module"
fi

# A module whose permissions exist but which no tenant has enabled is worth
# saying out loud: it is the state where a feature is built, shipped and off.
q "
  select f.feature_key || ': ' || count(cf.company_id) || ' tenant(s) enabled'
    from feature_catalog f
    left join company_feature cf on cf.feature_key = f.feature_key and cf.enabled
   group by f.feature_key order by 1" | while IFS= read -r l; do
  [ -n "$l" ] && printf '        %s\n' "$l"
done

# ── 4. A module table is gated by the PERMISSION, not only by tenancy ───────
#
# The pairs are declared here rather than discovered, because "which permission
# should guard this table" is a design fact and not something a query can infer.
head2 "4. Module tables are gated by their permission, not only tenancy"
check_table_gate() {
  local tbl="$1" key="$2"
  local exists; exists=$(q "select count(*) from information_schema.tables where table_schema='public' and table_name='$tbl'")
  if [ "$exists" != "1" ]; then warn "$tbl does not exist here yet; skipping"; return; fi

  local rls; rls=$(q "select relrowsecurity::text from pg_class where relname='$tbl' and relnamespace='public'::regnamespace")
  [ "$rls" = "true" ] && pass "$tbl has RLS enabled" || fail "$tbl has RLS DISABLED"

  # Any policy that permits a WRITE to authenticated and does not mention the
  # key is a policy that lets every tenant member write.
  local loose; loose=$(q "
    select policyname || ' (' || cmd || ')'
      from pg_policies
     where schemaname='public' and tablename='$tbl'
       and cmd in ('ALL','INSERT','UPDATE','DELETE')
       and 'authenticated' = any(roles)
       and coalesce(qual,'') || coalesce(with_check,'') not like '%$key%'
     order by 1")
  if [ -n "$loose" ]; then
    while IFS= read -r p; do
      [ -n "$p" ] && fail "$tbl policy $p permits writes without naming '$key': any tenant member may write"
    done <<< "$loose"
  else
    pass "$tbl write policies all name '$key'"
  fi
}
check_table_gate customer_chain customer.chain_manage
check_table_gate provider_credentials payments.credentials_manage
check_table_gate customer_payment_methods payment.saved_methods

# ── 5. A constraint must admit every value the code writes ──────────────────
head2 "5. Constraints admit the values the code writes"
check_check_admits() {
  local con="$1" word="$2"
  local def; def=$(q "select pg_get_constraintdef(oid) from pg_constraint where conname='$con'")
  if [ -z "$def" ]; then fail "constraint $con does not exist"; return; fi
  case "$def" in
    *"$word"*) pass "$con admits '$word'" ;;
    *)         fail "$con does NOT admit '$word'; the code that writes it will 500 on every attempt" ;;
  esac
}
check_check_admits payment_transactions_status_chk returned
check_check_admits orders_payment_status_chk returned

# The saved-method token columns must stay unreadable by authenticated.
head2 "6. Saved payment tokens stay unreadable"
TOK=$(q "
  select column_name from information_schema.column_privileges
   where table_schema='public' and table_name='customer_payment_methods'
     and grantee='authenticated' and privilege_type='SELECT'
     and column_name in ('provider_vault_customer_id','provider_payment_method_id')
   order by 1")
if [ -n "$TOK" ]; then
  while IFS= read -r c; do [ -n "$c" ] && fail "authenticated can SELECT customer_payment_methods.$c (a gateway token)"; done <<< "$TOK"
else
  pass "neither token column is readable by authenticated"
fi

# raw_response is the back door the same tokens leaked through once.
RAW=$(q "
  select count(*) from information_schema.column_privileges
   where table_schema='public' and table_name='payment_transactions'
     and grantee='authenticated' and privilege_type='SELECT' and column_name='raw_response'")
if [ "$RAW" = "0" ]; then
  pass "payment_transactions.raw_response is not readable by authenticated"
else
  warn "authenticated can SELECT payment_transactions.raw_response; it must never contain a vault id"
fi

printf '\n'
if [ "$FAILS" -eq 0 ]; then
  printf '\033[32mAll module-install checks passed.\033[0m\n'; exit 0
else
  printf '\033[31m%d module-install check(s) FAILED.\033[0m\n' "$FAILS"; exit 1
fi
