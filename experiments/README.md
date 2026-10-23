# Isolated watch UI experiments

Flutter on Wear OS and the community `flutter-watchos` toolchain are **evaluation options only**. Production baselines live under `apps/wear_os` (Kotlin/Compose) and `apps/watch_os` (SwiftUI/HealthKit). Do not add unsupported FlutterWatch toolchains to the stable mobile Dart workspace, and do not import experimental dependencies into release CI.

Create `experiments/wear_flutter/` or `experiments/watchos_flutterwatch/` **only when** a measurable real-device PoC is approved. Compare battery, memory, background workout reliability, watch UI accessibility, phone disconnect and TestFlight/Play distribution to native.
