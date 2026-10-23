# Firebase diagnostics — data minimization contract

**Provider decision:** Firebase Crashlytics + Firebase Analytics **replace** the former Sentry candidate under [ADR-0003](adr/0003-data-cloud-health.md). **No Firebase packages or project credentials are present in the current Flutter foundation.**

## Before enabling either SDK

1. Define purpose, legal basis/consent policy, disclosure, retention and user controls with a privacy review appropriate to shipped jurisdictions and Apple/Google policies.
2. Configure native and Dart defaults to **disable automatic collection before SDK initialization**, not merely hide a toggle in the UI. Verify Crashlytics crash collection and Analytics collection separately, including native startup/early crashes and user opt-out.
3. Use a typed, minimal allowlist of event names and static non-sensitive parameters: e.g. `screen_view`, `workout_flow_opened`, `workout_save_succeeded`, `permission_prompt_shown` with coarse flags only. No free-form values, identifiers or user data.
4. Filter/truncate error messages, exception causes, custom keys and breadcrumbs **before** they reach the SDK; ensure health/notes/token data cannot be embedded indirectly in stack-context or failed request diagnostics.
5. Health sample contents, workout values, user-entered notes, session/exercise identifiers, account emails, provider IDs, GPS routes, device pairing IDs, URLs containing personal data, access tokens and authorization headers are **forbidden** telemetry fields.
6. Use separate consent controls for usage analytics and diagnostics, default OFF until policies/controls exist. Consent revocation must stop future collection and respect SDK-specific handling of previously cached reports.
7. Test no upload before consent; opt-in; opt-out; offline queue; crash before consent, and redaction using deliberately sensitive synthetic fixtures. Enforce event-schema audits in code review.

Reporting a diagnostic problem cannot block workout saving. No silent tracing of health-platform requests, no raw Supabase payloads, and no copy of Firebase crash events in ObjectBox.

## Integration gate

Add Firebase dependencies/configuration only in a reviewed implementation PR with platform files, build variants and non-sensitive example events. Until then, use an inert `DiagnosticsSink` abstraction if needed. **Do not configure collection by default in this docs-only change.**
