# ADR-0001: Flutter foundation

Date: 2026-10-23. Status: accepted for scaffold.

Decide Flutter + Material 3 with custom Northstar Performance V2 semantic tokens; Riverpod for state AND DI; go_router for routing; shared_preferences for non-sensitive appearance; ObjectBox 5.x for transactional offline mobile data; native HealthKit/Health Connect through adapter interfaces only when permissions are reviewed; analytics/crash upload off by default pending privacy design.

Reject multiple DI frameworks, all-purpose key-value workout persistence, platform sniffing for tablet design, automatic health uploads, and unvalidated readiness scoring. Initial repository contains mocked Flutter UI but not live integrations; native runner and lockfile require Flutter SDK bootstrap. Changes to these commitments require a new ADR and review.

**Amendment 2026-10-23:** owner chose ObjectBox over Drift/SQLite. The Flutter project lists ObjectBox runtime/generator dependencies; persisted entities/Store lifecycle arrive with offline workout MVP. The separate wearable architecture decision is captured in [ADR-0002](0002-watch-workout-architecture.md). Watch databases are independent from the mobile ObjectBox store; synchronization is via contracts, not shared database files.
