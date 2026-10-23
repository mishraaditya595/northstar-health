# Reusable Dart packages

Intentionally no Dart workspace packages yet. `apps/mobile` is the sole Dart package and builds independently. Add `packages/workout_domain` / `packages/workout_protocol` only when code is genuinely shared across two supported Dart targets; then opt in to Dart pub workspaces and a root lockfile.

Kotlin and Swift consume **language-neutral** protocol schemas and common fixtures in `contracts/workout_sync/v1`, never Dart source directly. Keep experimental FlutterWatch SDK pinned outside the stable workspace.
