# ADR-0007 — Two recovery exits after an uncertain account deletion

**Status:** **Accepted** — explicitly decided by the human owner in the 2026-10-27 PR #29 review.
**Amends:** ADR-0005 item 4, P2-07c device-local recovery UX. Does not alter the authenticated server hard-delete rules, user isolation, or completed-only cloud backup.

## Context

A delete-account request may have failed before the server removed the Auth identity, or it may have committed and lost its HTTP receipt. Both cases retain an OS-secure original-owner recovery marker and keep the local ObjectBox partition locked. A single recovery exit that always erased local files risked destroying unsynced workouts when the cloud account still existed. Conversely, simply discarding a recovery marker without offering deletion could strand local data after a confirmed deletion whose secure cleanup marker could not be written.

## Human owner's decision (2026-10-27)

The recovery screen must expose **both independently confirmed choices**:

1. **Use another account (keep old data locked).** Clear the securely stored owner binding **first**, then clear the recovery marker. Do **not** delete the original owner's directory, sessions, custom plans, workout data or outbox. The directory stays keyed by the original Supabase project and verified Auth UUID; no other account is allowed to mount or inherit it. If that same original account still exists, successful reauthentication with the exact original UUID may reopen its files. The confirmation says the old workouts remain locked to their original account and are **not transferred**.
2. **Erase local data and leave.** Obtain a separate irreversible-loss confirmation identifying unsynced workouts, plans and pending uploads. Clear the owner binding, erase **only** the original owner's ObjectBox directory, and **then** clear the recovery marker. If erasure fails, retain the marker and require retry; never unlock another user or pretend success.

Both dialogs have a **Keep recovering** cancel action. Cancel does not change the binding, marker or local files. These choices remain available during uncertain recovery; no auto-erasure may occur solely because recovery is pending.

A freshly verified and explicitly confirmed server deletion still permits automatic deletion of the original owner's local files as part of the original deletion consent. A lost or unknown server receipt does **not** permit automatic local erasure. The keep-data exit does not claim any cloud deletion and never resurrects a deleted Auth identity.

## Verification and consequences

- Verify keep-data retention on disk and same-UUID reopening; switching to another verified UUID must never expose the original partition.
- Verify independent UI confirmations and unchanged state on cancellation.
- Verify erasure order, failed-erase retained marker and retry, existing confirmed-success cleanup behavior, and no-erasure-on-uncertain-response tests.
- All cloud-account deletion, hosted Auth/RLS, old-token and Android/iOS filesystem/keychain integration proof remain P2-08 release gates.

**Approval evidence:** This policy choice was made explicitly by the project owner in the PR #29 review thread on 2026-10-27; this ADR records that request. Agent-authored code and prose are not independent security sign-off or permission to merge.
