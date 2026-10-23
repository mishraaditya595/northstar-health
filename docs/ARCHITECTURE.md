# Architecture and technology decisions

## Stack
| Concern | Decision | Notes |
| --- | --- | --- |
| App | Flutter Material 3 + Northstar tokens | One codebase, adaptive patterns |
| State and dependency injection | **flutter_riverpod 3** | Providers and notifiers; no service locator |
| Routes | **go_router** | App-level paths, deep-link ready |
| Durable local data | **Drift + SQLite** | Selected for future sessions/sets, migrations, transactions and queries. **Not yet installed** |
| App settings | **shared_preferences** | Theme and nonsensitive flags only |
| Health | HealthKit (iOS), Health Connect (Android) via reviewed adapter | Future; explicit read/write permissions, sources and unit conversion |
| Crash reports | Opt-in Sentry candidate | **Not installed**; disable PHI fields, breadcrumbs and event upload until privacy review |
| Analytics | Opt-in typed allowlist candidate | **Not installed**; never send health values, notes, IDs or provider payloads |
| Backend | None initially | Start fully offline; sync requires its own ADR |
| CI | format, static analysis, tests | Device integration/build signing later |

## Project boundaries

```
platform APIs -> adapters -> repositories -> local SQLite -> Riverpod -> widgets
workout UI -> notifier -> repository -> transaction -> persisted success -> optional sync
```

Features live in `lib/features/<feature>/`. Add `domain` and `data` folders when implementation needs them, not as empty scaffolding. `lib/app` owns root routing/layout; `lib/core` owns tokens and shared utilities. No network or sensor activity from `build()`.

### Low-end-device guidance
Use const widgets, split provider listening by subfeature, lazy lists, avoid repeated image decoding/blur/shader work, no expensive parsing or joins on the UI isolate, load historical samples in bounded pages, aggregate off-main when heavy, avoid unbounded retention/caches. Profile jank on entry-level Android before introducing animation or caching frameworks. A rest timer must not rebuild an entire dashboard every second.

### Adaptive guidance
Under 600 logical px: NavigationBar and narrow cards; 600+ when available: NavigationRail and max-width bounded content. Over 840: multi-column panels where useful. Use `LayoutBuilder` not platform/rotation checks. Respect safe areas, scaling, foldables and keyboards.

## Delivery truth
Current native code implements only themed fixture screens, router and theme switch. Persistence, actual workout operations, integrations, consent and crash collection are **future work**.
