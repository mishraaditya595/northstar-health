# Architecture and technology decisions

## Stack
| Concern | Decision | Notes |
| --- | --- | --- |
| App | Flutter Material 3 + Northstar tokens | One codebase, adaptive patterns |
| State and dependency injection | **flutter_riverpod 3** | Providers and notifiers; no service locator |
| Routes | **go_router** | App-level paths, deep-link ready |
| Durable local data | **ObjectBox 5.x** | Mobile object persistence; versioned model, transactions, indexed queries and generated bindings (dependency configured; database initialization deferred until first persistent entities) |
| App settings | **shared_preferences** | Theme and nonsensitive flags only |
| Phone health | HealthKit (iOS), Health Connect (Android) via reviewed adapter | Future; explicit read/write permissions, sources and unit conversion |
| Watch capture | HealthKit workout sessions (watchOS), Health Services ExerciseClient (Wear OS) | Native background sensor/session engine; watch UI under evaluation |
| Phone-watch protocol | Versioned durable command/event queue | Explicit IDs, ACK/retries/idempotency, reconciliation and offline writes |
| Crash reports | Opt-in Sentry candidate | **Not installed**; disable PHI fields, breadcrumbs and event upload until privacy review |
| Analytics | Opt-in typed allowlist candidate | **Not installed**; never send health values, notes, IDs or provider payloads |
| Backend | None initially | Start fully offline; sync requires its own ADR |
| CI | format, static analysis, tests | Device integration/build signing later |

## Project boundaries

```
phone HealthKit/Health Connect -> adapters -> repositories -> mobile ObjectBox -> Riverpod -> widgets
workout UI -> notifier -> repository -> transaction -> persisted success -> optional sync
```

Features live in `lib/features/<feature>/`. Add `domain` and `data` folders when implementation needs them, not as empty scaffolding. `lib/app` owns root routing/layout; `lib/core` owns tokens and shared utilities. No network or sensor activity from `build()`.

### Low-end-device guidance
Use const widgets, split provider listening by subfeature, lazy lists, avoid repeated image decoding/blur/shader work, no expensive parsing or joins on the UI isolate, load historical samples in bounded pages, aggregate off-main when heavy, avoid unbounded retention/caches. Profile jank on entry-level Android before introducing animation or caching frameworks. A rest timer must not rebuild an entire dashboard every second.

### Adaptive guidance
Under 600 logical px: NavigationBar and narrow cards; 600+ when available: NavigationRail and max-width bounded content. Over 840: multi-column panels where useful. Use `LayoutBuilder` not platform/rotation checks. Respect safe areas, scaling, foldables and keyboards.

## Delivery truth
Current native code implements only themed fixture screens, router and theme switch. Persistence, actual workout operations, integrations, consent and crash collection are **future work**.

## Watch platform plan

See [Wearables](WEARABLES.md), [Sync protocol](SYNC_PROTOCOL.md), and [ObjectBox](OBJECTBOX.md). The mobile ObjectBox database does **not** imply watchOS Flutter ObjectBox support or a shared database file. Watch apps use independent durable storage via supported native platform facilities until runtime compatibility is proven. Keep domain protocol portable across Dart/Kotlin/Swift.
