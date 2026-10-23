# ADR-0001 — Flutter foundation

**Date:** 2026-10-23 · **Status:** Accepted, amended by [ADR-0003](0003-data-cloud-health.md) for backend, cloud backup and diagnostics.

NorthStar mobile uses Flutter/Material 3 with NorthStar Performance V2 tokens; Riverpod for state **and** dependency injection; go_router for routes; shared_preferences only for nonsensitive appearance; **ObjectBox** for future durable local workout/session data. Responsive layouts choose navigation based on available width, not tablet device sniffing.

The initial prototype includes mock fixture screens without live device readings, credentials, health permissions or cloud/network features. First native runner generation, lockfile, full local schema and integration builds are separate implementation tasks.

**Superseded decisions:** An earlier foundation revision deferred backend selection and identified Sentry as a candidate. [ADR-0003](0003-data-cloud-health.md) now selects **Supabase Auth/PostgreSQL** for **completed-workout-only backup** and **Firebase Crashlytics/Analytics** as future privacy-gated diagnostics. There is no active SDK, default collection or cloud data pipeline in the foundation. Do not implement the old Sentry plan.

**Related:** [ADR-0002](0002-watch-workout-architecture.md) for smartwatch native workout service / UI experimentation.
