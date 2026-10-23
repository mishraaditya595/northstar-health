# Instructions for all Northstar coding, design and review agents

**Read before any changes:** `README.md`, `docs/ARCHITECTURE.md`, `docs/DESIGN_SYSTEM.md`, `docs/HEALTH_DATA.md`, `docs/OBJECTBOX.md`, `docs/WEARABLES.md`, `docs/SYNC_PROTOCOL.md`, and `docs/REVIEW_GUIDE.md`. Additional local instructions may strengthen, never weaken, this contract.

## Workflow
1. Inspect current code and impacted tests, then write a focused implementation plan.
2. Work on a dedicated branch, make small reviewable changes, and update docs and ADRs for architectural changes.
3. Keep domain logic and native APIs out of widgets. Use Riverpod for state and DI, go_router for app navigation, and feature-first file boundaries.
4. Use the **Performance V2** reference under `prototypes/performance-v2/`, not arbitrary generic health templates. Keep the reference files unmodified unless requested.
5. Provide working compact and expanded layouts based on available width, not device identity; support iPad split view, Android multiwindow, portrait, landscape and dynamic text sizing.
6. Test dark **and** light theme, loading/empty/error states, keyboard focus, accessibility and reduced motion.
7. Never invent health data or show unavailable measurements as zero. Always provide source, units and time when displaying real measurements.
8. Use ObjectBox for mobile durable workout and health persistence; the generated `objectbox-model.json` is a versioned schema artifact and MUST be committed with IDs intact. Workout saves must be transactional and durable before showing success. Any health import must be permissioned, deduplicated and sourced.
9. Do not add telemetry, raw health logging, permissions, SDKs or dependencies without privacy review and ADR.
10. Run `dart format lib test`, `flutter analyze`, `flutter test` where possible; clearly state unavailable checks. Require an independent reviewer; don't self-approve/merge.

## PR handoff
State problem, solution, screens, privacy impact, tests actually run, screenshots at phone/tablet widths in both modes, limitations, and rollback. Reviewers inspect the real diff, not claims. Do not commit secrets, wearable exports, account keys, or generated personal data.

## Watch-app rules
- Do not assume stock Flutter supports watchOS or that phone health aggregation is the same as live on-watch recording.
- Keep sensor acquisition, session lifecycle and screen-off behavior native: watchOS HealthKit sessions, Wear OS Health Services `ExerciseClient` and foreground service.
- Treat FlutterWatch/watchOS and Flutter/Wear OS as gated prototypes, not production promises; document SwiftUI/Compose fallback.
- Every watch action must commit locally first, enqueue a versioned idempotent event and reconcile after reconnect. Never claim delivery just because a connectivity plugin returned success.
- Every watch feature requires real-device tests for screen-off, process interruptions, phone disconnect, battery, and release signing. See `docs/WEARABLES.md` and `docs/SYNC_PROTOCOL.md`.
