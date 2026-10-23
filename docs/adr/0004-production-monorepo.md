# ADR-0004 — Production monorepo with independent watch applications

**Date:** 2026-10-23  
**Status:** Accepted structure, initial build scaffolding

## Decision

Keep `apps/mobile` as the sole Flutter application package for Android/iOS phones and tablets; `apps/wear_os` as an independent Android watch Gradle application; and `apps/watch_os` as the **single source location** for native SwiftUI watch source. The current watchOS `project.yml` provides a stand-alone compile target. Its final Xcode companion embedding/signing relationship with `apps/mobile/ios/Runner` is **not yet implemented** and remains a release-blocking integration gate.

`contracts/workout_sync/v1` is a portable JSON schema and set of shared fixtures, not a shared Dart library. Source-specific agent instructions apply in each app directory. Root `docs`, `prototypes`, `supabase`, `packages`, and `experiments` remain separate.

Do not create a root Dart pub workspace until there is more than one production Dart package. Never require the custom FlutterWatch engine to build mobile or stable watch targets.

## Why

The prior repository had Flutter sources at root and no committed platform runners. Reorganize before completing native Flutter bootstrap to avoid changing Android/iOS project paths after products rely on them. Native watch-session ownership, independent local journaling and two-stage ACKs remain per ADR-0002/0003. No watch SDK is enabled by this structural PR.

## Consequences and verification gates

1. Flutter 3.47.7 and Dart package resolution/checks run from `apps/mobile` only.
2. Reviewed version-controlled iOS/Android runners and `apps/mobile/pubspec.lock` become mandatory.
3. Wear OS must have a reproducible Gradle Wrapper, Android SDK/JDK build and a signed eventual Play artifact.
4. watchOS XcodeGen spec must compile on macOS; the **same Swift sources** must be integrated with a real Runner companion target, verified through iPhone/watch signing, archive and TestFlight.
5. Contract schemas/fixtures and schema compatibility tests gate any cross-language event changes.
6. No HealthKit, Health Connect, telemetry, ObjectBox Store, Supabase or live workout lifecycle is claimed yet.

**Supersedes nothing about data ownership or UI**: ADR-0001, ADR-0002 and ADR-0003 continue to apply.
