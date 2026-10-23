# Scope and roadmap

**Foundation** (this PR): preserved web prototype, Flutter fixture dashboard, adaptive navigation, themes, docs and CI. No live sensors, workouts, authentication or backup.

**Workout MVP (ObjectBox):** exercise catalog, custom plans, live sets/rest, pause/resume, crash-proof ObjectBox writes, history, migrations, export/delete and exercise trends.

**Health integration:** opt-in HealthKit/Health Connect, permissions, sync source/timestamp, unit normalization, selective import/deduplication, empty/denied/stale states.

**Insights:** transparent adherence, simple strength trends, sleep/activity dashboards with provenance and no diagnostic advice.

**Later:** backend and optional cross-device sync only after privacy, identity, encryption, conflict, storage and consent architecture is reviewed. Wearable companion apps and third-party APIs are separate decisions.

**Wearable architecture & proof of concept:** early in development, define shared event contracts and phone/watch synchronization, then evaluate Flutter on Wear OS against Compose and FlutterWatch on watchOS against SwiftUI using a complete hardware-backed workout flow. Platform-native session engines are required. Wrist-first capabilities: start/pause/resume/end, set reps and load, rest timer with haptics, live supported heart rate, offline set saving, disconnected reconciliation. Release requires measured reliability, battery, performance and signing. See [WEARABLES.md](WEARABLES.md).
