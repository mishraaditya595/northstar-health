#!/usr/bin/env bash
# Runs native ObjectBox tests on a local macOS checkout without a system-wide install.
set -euo pipefail
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script is for macOS. Linux CI provisions its own ObjectBox library." >&2
  exit 2
fi
command -v flutter >/dev/null || { echo "Flutter SDK is required" >&2; exit 2; }
command -v shasum >/dev/null || { echo "shasum is required" >&2; exit 2; }
command -v unzip >/dev/null || { echo "unzip is required" >&2; exit 2; }
cd "$(dirname "$0")/.."
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
url="https://github.com/objectbox/objectbox-c/releases/download/v5.3.2/objectbox-macos-universal.zip"
curl --fail --location --retry 3 --silent --show-error "$url" -o "$scratch/objectbox.zip"
echo "680c598573ede04b9762565d48d4e161ad286f786f159abb8da89353bfa1d0bc  $scratch/objectbox.zip" | shasum -a 256 -c -
unzip -q "$scratch/objectbox.zip" -d "$scratch/extracted"
native="$(find "$scratch/extracted" -type f -name libobjectbox.dylib -print -quit)"
if [[ -z "$native" ]]; then
  echo "Pinned ObjectBox archive did not contain libobjectbox.dylib" >&2
  exit 3
fi
export DYLD_LIBRARY_PATH="$(dirname "$native")${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
cd apps/mobile
flutter pub get --enforce-lockfile
flutter test
