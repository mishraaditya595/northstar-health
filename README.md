# Northstar Health

An offline-first Flutter health and strength-training companion for Android, iOS, iPad and Android tablets. **Status: foundation/demo, not a live health integration.**

## Start here
- [Agent instructions](AGENTS.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Design system](docs/DESIGN_SYSTEM.md)
- [Health data and privacy](docs/HEALTH_DATA.md)
- [Agent review protocol](docs/REVIEW_GUIDE.md)
- [Implementation roadmap](docs/ROADMAP.md)

## Repository

```
lib/
  app/                       # app shell and adaptive routing
  core/design/               # theme and design tokens
  features/                  # today, train, progress, health
test/                        # widget tests
docs/                        # decisions, instructions and product constraints
prototypes/performance-v2/   # preserved original, runnable HTML/CSS/JS
.github/                     # PR template and CI
```

## Flutter setup
Requires Flutter SDK 3.47.7 and Dart 3.13. On macOS install Xcode/CocoaPods and Android SDK for native builds. **Platform folders and pubspec.lock are not generated yet** (Flutter SDK unavailable in authoring environment). Once on your machine:

```sh
flutter create --platforms=android,ios --project-name=northstar_health --org=dev.northstar .
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter run
```

Review bundle identifiers, minimum deployment versions, privacy entitlements and platform settings before committing generated `android/`, `ios/` and `pubspec.lock`. CI bootstraps transient runners.

## Original prototype
```sh
cd prototypes/performance-v2
python3 -m http.server 4173
```
Then open http://localhost:4173. The HTML prototype includes more mocked journeys than this native foundation; no wearable permissions, device readings, authentication, or backups are live.

All sample metrics are fictional. Do not infer medical advice from them.
