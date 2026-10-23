# Wear OS agent instructions

Inherits ../../AGENTS.md. This folder is a standalone Android Wear OS application (Kotlin/Compose).

- Future workout recording must be owned by Kotlin Health Services `ExerciseClient` and the appropriate Android foreground service, with independent durable watch-side storage and an outbox.
- Keep UI, session manager, persistence and transport distinct. No workout completion claims until local persistence confirms success.
- Sync events conform to `contracts/workout_sync/v1`; app-to-app Data Layer delivery != phone ObjectBox or Supabase ACK.
- Do not add Health Services permissions before implementing and testing the feature and documenting Play policies/consent.
- Build from `apps/wear_os` using Gradle (install Android SDK 35/JDK 17). Release must be validated on small/large round devices and physical watch.
