# Wear OS agent instructions

Inherits ../../AGENTS.md. This folder is a standalone Android Wear OS application (Kotlin/Compose).

- `core/` is a JVM-only module (codecs, replay, session machine, journal over the `SqlDatabase` interface) with no `android.*` import; `app/` holds Android code and depends on it. Test the core with `./gradlew :core:test -Pbeyondrep.coreOnly=true` (skips `:app`, needs no Android SDK). The core must keep running the golden files under `contracts/`.
- The watch journal is the durable record: state and the outbound message commit in one transaction, and a completed workout is resent until the phone's `ack` (ADR-0015, ADR-0012). The app ID is the phone's, `in.beyondrep.app`, for the Data Layer.
- Future workout recording must be owned by Kotlin Health Services `ExerciseClient` and the appropriate Android foreground service, with independent durable watch-side storage and an outbox.
- Keep UI, session manager, persistence and transport distinct. No workout completion claims until local persistence confirms success.
- Sync events conform to `contracts/workout_sync/v1`; app-to-app Data Layer delivery != phone ObjectBox or Supabase ACK.
- Do not add Health Services permissions before implementing and testing the feature and documenting Play policies/consent.
- Build from `apps/wear_os` using Gradle (install Android SDK 35/JDK 17). Release must be validated on small/large round devices and physical watch.
