# ADR-0001: Flutter foundation

Date: 2026-10-23. Status: accepted for scaffold.

Decide Flutter + Material 3 with custom Northstar Performance V2 semantic tokens; Riverpod for state AND DI; go_router for routing; shared_preferences for non-sensitive appearance; Drift/SQLite for future transactional offline data; native HealthKit/Health Connect through adapter interfaces only when permissions are reviewed; analytics/crash upload off by default pending privacy design.

Reject multiple DI frameworks, all-purpose key-value workout persistence, platform sniffing for tablet design, automatic health uploads, and unvalidated readiness scoring. Initial repository contains mocked Flutter UI but not live integrations; native runner and lockfile require Flutter SDK bootstrap. Changes to these commitments require a new ADR and review.
