# P2-06 — Mobile restore transport and validated decoding

**Scope:** First Flutter portion of P2-06 following merged PR #18 (server restore feed). **Not end-to-end restore; not deployed.** Branch: feat/p2-06-mobile-restore-transport.

## Implemented in this slice

- Pure WorkoutRestorePage.decode strictly validates the exact schema_version:1 envelope, cursor_epoch, cursor reset/next cursor, page bounds, and ordered server change sequence. Invalid remote content fails before any local mutation or cursor advance.
- A new device bootstraps with cursor 0 and no epoch. Subsequent pages echo the server-issued epoch. Mismatched epoch is only accepted as a reset with an empty page and next_cursor zero; an ordinary stale page is rejected even when restored-server writes have already overtaken the device cursor.
- Decodes completed NorthStar phone workout snapshots to an immutable *remote snapshot* model, separate from local optimistic-lock WorkoutSessionRecord; the serverRevision stays solely on the change envelope so an importer cannot mistake it for the local revision. Explicit allowlists reject unexpected fields and platform health measurements while matching the server's actual required/optional exercise and set keys (no rejection of omitted muscle/equipment/rpe). The decoder accepts UTC Z, at least every server-valid ±HH:MM offset (the client parser also accepts some larger offsets the server rejects), end-of-day 24:00:00 and leap seconds, enforces uniqueness independently for exercise IDs and set IDs, and checks timestamp, units, load, RPE and nesting/64 KiB limits. Tombstones never contain workout payloads.
- SupabaseWorkoutRestoreTransport uses a shared upload/restore session predicate before and after the RPC. Its identity reader, RPC invoker and clock are injectable for tests, including account switching or token expiration while HTTP is in flight. Auth expiry throws a retryable AuthException (no local cursor advanced). Server RLS and auth.uid remain authoritative.
- The transport is exposed behind a provider factory but is **not mounted in the app**. No polling, data mutation, automatic restore, local cursor advance or upload can occur from this implementation alone.
- Unit tests cover the actual SQL server fixture, valid UTC offsets, optional nested fields, exercise/set ID-domain independence, invalid epochs and same-epoch reset, overtaken stale cursors, cursor/limit bounds, malformed keys/types, tombstones, nested health-field rejection, and a genuinely >64 KiB payload of valid sets. PostgreSQL UUID aliases, canonical collisions, temporal boundary normalization, non-PII failure codes and the production fromClient smoke test are also covered. Dedicated transport tests exercise the exact RPC arguments, preflight validation, invalid account/anonymous session, in-flight account switch, retryable expiry, and response errors.

## Compatibility and failed-page recovery contract

The decoder **accepts PostgreSQL UUID input spellings** (mixed-case hexadecimal, braces, omitted separators and a separator after any four hex digits) and normalizes them to standard lower-case UUIDs for local identity. It accepts at least every server-valid ISO timestamp offset (and some ±16:00–23:59 offsets the server would reject), **24:00:00** (next-day midnight) and **:60** leap seconds (following minute) while retaining the instant in UTC.

**Accepted limitation, no server migration in this PR:** The P2-01 database validator compares exercise and set UUIDs as *strings*, so it can accept two different spellings that represent the **same UUID** within one domain. ObjectBox cannot safely materialize both under one canonical ID; do **not** silently rename one or merge the records. The decoder raises `duplicate_exercise_id` or `duplicate_set_id` and blocks that page. A future additive server migration may canonicalize/reject duplicate semantic UUIDs for *new writes*, but historical rows need an audited remediation plan. Until then, this ambiguity is intentionally fail-closed rather than an automatic merge or drop.

**Required importer behavior for any permanently invalid row (not yet implemented):**

1. Decode/validate a fetched page **before** opening a write transaction. On `RestoreContractException`, preserve the last **durably committed** account-bound `(cursor_epoch, next_cursor)`, all local sessions and all pending/blocked/conflicted operations. **Never skip a row, advance the cursor, or import part of a rejected page.**
2. Record a bounded **owner-scoped** restore-blocked state with a stable non-PII `error.code` (for example `invalid_uuid`, `invalid_timestamp`, `duplicate_set_id`, `unsupported_field`, `payload_too_large`, `epoch_mismatch`). Never store the invalid payload, raw RPC exception, free-text notes or account/workout IDs in telemetry. The public error message is generic; invalid caller arguments report **"Invalid workout restore request"**.
3. Stop automatic retries for deterministic validation failures after the first confirmed failure; keep a user-visible **"Cloud restore needs attention"** recovery action. This avoids an infinite repeat of the same blocking page. Network/authentication expiry remains retryable separately and does not mutate the cursor.
4. Resolution requires a reviewed server-side correction/normalization or a product-approved manual recovery mechanism. After correction, explicitly retry from the **unchanged cursor and epoch** (or from zero if the server signals epoch reset). Do not auto-delete, discard, or pretend the blocked record was successfully restored. A user-initiated diagnostic export, if added later, must contain reason codes only and require consent.
5. Add interrupted-page, restart, account-switch, tombstone, and malformed-record tests for the eventual ObjectBox importer and its durable blocked state. This PR deliberately adds **only the safe contract and decoder exception type**, not persistence or a fake recovery UI.

**Code vocabulary for future durable blocked state:** treat `RestoreContractException.code` values as stable, non-PII diagnostic categories, **not** instructions. The decoder distinguishes:
- **Envelope/paging:** `invalid_schema_version`, `invalid_page_flags`, `invalid_cursor_reset`, `invalid_page_limit`, `invalid_change_order`, `invalid_next_cursor`, `invalid_delete_flag`, `invalid_change_payload`, `epoch_mismatch`, `too_many_changes`.
- **Identity and shape:** `invalid_uuid`, `duplicate_workout_id`, `duplicate_exercise_id`, `duplicate_set_id`, `invalid_object`, `missing_field`, `unsupported_field`, `invalid_list`, `invalid_number`, `invalid_text`.
- **Workout:** `invalid_workout_schema`, `workout_id_mismatch`, `invalid_workout_origin`, `invalid_workout_status`, `invalid_original_offset`, `invalid_workout_time_order`, `too_many_exercises`.
- **Sets:** `invalid_set_kind`, `invalid_set_status`, `invalid_set_unit`, `invalid_set_rpe`, `invalid_set_completion`, `invalid_set_time_order`, `invalid_set`, `too_many_sets`.
- **Time and payload:** `invalid_timestamp`, `invalid_timezone_offset`, `invalid_payload`, `payload_too_large`. Invalid caller arguments use `invalid_request` and `request=true`.

The error has **no** `shouldAdvanceCursor` decision property. The future importer must advance the cursor **only after successfully committing the entire validated page and its cursor/epoch in one owner-bound transaction**, never based on an exception property or error-code allowlist. Any error, including new or unknown codes, is fail-closed. Test cases include a leap second at midday, fractional leap seconds, unpaired UUID braces, and zero month/day.

## Required follow-up to make actual cloud restore usable

1. Introduce versioned ObjectBox metadata for owner-bound remote revisions, tombstones and local conflict state plus durable cursor_epoch and next_cursor. Preserve entity/property/index UIDs and commit generated code and old-version fixture upgrade tests.
2. Add a crash-atomic importer which validates and reconciles session/exercise/set snapshots and tombstones and commits each page's cursor+epoch in the same owner-scoped transaction. Imports must not create new upload operations.
3. Never overwrite pending, blocked, conflicting or ambiguous local workout edits; preserve on-device data and present explicit recovery choices. Do not resurrect tombstones.
4. Add a foreground pull coordinator serialized with the upload worker, safely handling network outages, account switch, cancellation, process restart, and cursor reset full replay.
5. Fix queued-op first-500 starvation and dependencies; complete two-account live JWT/RLS, real device cross-phone restore, schema upgrade and epoch/PITR staging tests.

**Deployment:** Changes are limited to Flutter code, tests and docs. There is no Supabase deployment or enabled mobile restore. Server epoch rotation after database restore remains mandatory per supabase/RESTORE_RUNBOOK.md. The P2-06 milestone remains incomplete.

## Validation

Use the repository-pinned Flutter toolchain and mobile CI: dart format --output=none --set-exit-if-changed lib test, flutter analyze, flutter test and Android debug build. There is no local Flutter SDK in the authoring environment, so use the PR checks as verification evidence.
