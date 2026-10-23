# Flutter mobile agent instructions

Inherited rules: ../../AGENTS.md. The Flutter project root is **apps/mobile**, not repository root.

- Flutter 3.47.7; package name `northstar_health`; Riverpod for state/DI; go_router for navigation; ObjectBox for durable workout and bounded permitted cache.
- Run commands from here: `flutter pub get`, `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test`, `flutter build apk --debug`.
- Use feature-first modules. Place native integrations behind repositories/platform adapters; never access HealthKit, Health Connect, Supabase or Firebase directly from widgets.
- iOS and Android runners are version controlled. Never overwrite native project files with `flutter create` during routine feature work; first-generation bootstrap is tracked in the migration PR.
- Any iOS watch companion ultimately requires real Xcode target/embedding configuration. Source-of-truth watch Swift files live at `../watch_os/Sources`, **not** duplicated within the Runner.
- Signed-off native plugin changes require real device smoke checks, permissions and telemetry default-off validation.
