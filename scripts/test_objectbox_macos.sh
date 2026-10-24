#!/usr/bin/env bash
# Test-only native ObjectBox library for a macOS checkout.
# Flutter launched through an OS-protected shell may drop DYLD_LIBRARY_PATH;
# placing the verified dylib in the test working directory avoids that issue.
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script is for macOS; Linux CI installs its own ObjectBox library." >&2
  exit 2
fi
for tool in flutter curl shasum unzip find mktemp; do
  command -v "$tool" >/dev/null || {
    echo "Missing required tool: $tool" >&2
    exit 2
  }
done

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$repo_root/apps/mobile"
target="$app_dir/libobjectbox.dylib"
scratch="$(mktemp -d)"
installed=false

cleanup() {
  if [[ "$installed" == true ]]; then rm -f "$target"; fi
  rm -rf "$scratch"
}
trap cleanup EXIT

# Never replace/delete an existing file that was not installed by this script.
if [[ -e "$target" || -L "$target" ]]; then
  echo "Refusing to overwrite existing $target; move it yourself first." >&2
  exit 3
fi

url="https://github.com/objectbox/objectbox-c/releases/download/v5.3.2/objectbox-macos-universal.zip"
curl --fail --location --retry 3 --silent --show-error "$url" \
  -o "$scratch/objectbox.zip"
echo "680c598573ede04b9762565d48d4e161ad286f786f159abb8da89353bfa1d0bc  $scratch/objectbox.zip" \
  | shasum -a 256 -c -
unzip -q "$scratch/objectbox.zip" -d "$scratch/extracted"
native="$(find "$scratch/extracted" -type f -name libobjectbox.dylib -print -quit)"
if [[ -z "$native" ]]; then
  echo "Pinned library archive did not contain libobjectbox.dylib" >&2
  exit 3
fi

# Set the cleanup ownership flag *before* copying. Even an interrupted
# or failed cp may leave a partial dylib, which must not survive the trap.
installed=true
cp "$native" "$target"
cd "$app_dir"
flutter pub get --enforce-lockfile
flutter test "$@"
