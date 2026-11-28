# ADR-0015 — Wear OS companion

**Status:** **Accepted** — approved by the project owner on 2026-11-27 (Adi approved the design). Stage 1 (the pure-Kotlin watch core) is implemented in source, not released or device-verified; stages 2 to 5 are not started.
**Builds on:** [ADR-0012](0012-apple-watch-companion.md) (decisions 3, 5, 6 and 7 apply unchanged) and the planned ADR-0014 (the phone writes workouts to Health Connect; being designed in a separate thread and not in the repository yet). **Amends:** ADR-0012 decision 4 and [HEALTH_DATA.md](../HEALTH_DATA.md) when stage 3 lands. Design: [Wear OS companion](../superpowers/specs/2026-11-27-wear-os-companion-design.md).

## Decisions

1. **Native companion.** The Wear OS app is native Kotlin with Compose for Wear OS, built in `apps/wear_os/`. It is not Flutter.
2. **Same app ID and signing key as the phone.** The watch app's `applicationId` is `in.beyondrep.app` (the Kotlin namespace stays `in.beyondrep.wear`), because the Wear Data Layer only connects apps that share both. The watch build is signed with the phone's key.
3. **Same rules as the Apple Watch.** ADR-0012 decision 3 (completed watch workouts are backed up once, by the phone, after its durable import), decision 5 (HMAC account key; the watch has no Supabase session) and decision 6 (the device that starts a session owns it) apply to Wear OS. Decision 7 (shared formula library) is not reconsidered.
4. **Transport is the Wear Data Layer.** Application-context calls map to one `DataItem` per type at `/context/<type>`, queued transfers to `DataItem`s at `/queue/<direction>/<message_id>` deleted after handling, live messages to `MessageClient`, and reachability to `NodeClient` and the `beyondrep_watch_app` capability (design 5.2). A Data Layer delivery is not a phone ObjectBox or Supabase acknowledgement; the phone's `ack` message is.
5. **Heart rate and calories of a watch workout reach Health Connect through the phone** (design 4.3, including consent, retention and phone-owned workouts), not from the watch. This amends ADR-0012 decision 4 and HEALTH_DATA.md when stage 3 lands; nothing changes before then.
6. **One tested core.** `apps/wear_os/core` is a JVM-only Gradle module with no `android.*` import. It holds the contract codecs, replay, session machine, command applier, state and completed-workout builders, the phone inbox and the SQLite journal (over a small `SqlDatabase` interface). It runs the same golden fixtures and cases under `contracts/` as Swift and Dart. The journal has one schema version (Swift journal v8 without the `links` table, because Wear sends no `workout_link`).

## Stages

1. Watch core (this ADR's source: `:core` tests, app ID, placeholder UI only).
2. Link and glance: phone Data Layer bridge, watch Home and Train pages, phone watch status.
3. Workout recording with Health Services and Health Connect heart rate and calories.
4. Live link both ways.
5. The watch's own health (steps and heart rate through passive monitoring).

## Consequences

- Nothing is released or device-verified. Stage 1 adds no permission, no screen and no data flow: `AndroidSqlDatabase` exists but nothing calls it.
- `:app:assembleDebug` runs on GitHub CI only; the local container has no Android SDK.
- Not ported from Swift in stage 1: journal migrations from older Swift schema versions (no Wear database exists) and `workout_link`.
