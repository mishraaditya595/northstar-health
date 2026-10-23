# ADR-0002: Watch workout architecture and bounded Flutter experiments

Date: 2026-10-23. **Status: Accepted direction; UI selection deferred pending device proof**.

Mobile remains Flutter. Watch-based strength workout logging and live available vitals become first-class *planned* functionality. They need independent device-local persistence and versioned, idempotent phone/watch syncing. Native session engines are mandatory: HealthKit `HKWorkoutSession`/`HKLiveWorkoutBuilder` for watchOS and Health Services `ExerciseClient` for Wear OS.

Evaluate Flutter UI on Wear OS against Compose; evaluate third-party FlutterWatch on supported Apple Watches against SwiftUI. Native SwiftUI/Compose are production alternatives; no release dependency on custom Flutter watchOS engine until real workout, battery, signing and compatibility gates pass. Flutter mobile ObjectBox is not assumed available on watchOS.

Research basis: user-provided NorthStar smartwatch research dated 2026-10-23. Architecture detail in [WEARABLES.md](../WEARABLES.md) and [SYNC_PROTOCOL.md](../SYNC_PROTOCOL.md).
