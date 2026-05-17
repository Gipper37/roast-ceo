# Archived migrations (pre-squash)

These 385 migrations spanning 2026-02-23 → 2026-05-16 captured the
incremental evolution of the schema before STRATA's v1 release. They
were squashed into a single canonical baseline (see
`../00000000000000_baseline.sql`) because:

1. **Filename-order replay didn't work.** Several early migrations
   referenced tables that were only created by later migrations. On
   prod this was never visible because migrations were applied in
   author order, not filename order. On a clean rebuild (staging or
   local dev), filename order is the only order, and the gaps
   surfaced immediately.
2. **The system was never released.** Squashing pre-release history
   loses nothing customers depend on.

These files are kept here for `git blame` + archaeology — if you want
to know when a particular column or trigger was introduced, `git log
supabase/migrations/_archive/<file>` still works.

**Do not move files back into `supabase/migrations/` directly.** The
baseline already contains everything these files set up. Adding them
back would cause duplicate-object errors on replay.

For new schema changes, create a fresh migration at the current
timestamp (`supabase migration new <name>`).
