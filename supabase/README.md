# Supabase — reserved production backend boundary

Data architecture: **Supabase Auth + Postgres**, for authenticated backup of **completed NorthStar-owned workout logs** only. No migrations or cloud schema are implemented in this repository restructuring PR.

Future migrations and RLS tests live in `supabase/migrations/` and `supabase/tests/`. Before deploy: authenticated owner RLS and cross-user negative tests, transactionally enforced aggregate revisions, idempotent operation IDs, deletion/tombstones, rate/size limits, and explicit account-switch/guest association.

**Never upload ObjectBox files, raw health observations, watch sensor streams, or the user's local custom plans in the initial cloud scope.** No service-role key in mobile/watch clients. See ../docs/CLOUD_SYNC.md.
