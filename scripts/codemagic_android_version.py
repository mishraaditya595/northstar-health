#!/usr/bin/env python3
"""Resolve the Google Play version name and version code for Codemagic.

Inputs (from the manual build form, via environment variables):
  NS_RELEASE_TYPE  Fix or optimisation, Feature, Major, Same version, new
                   build, or Exact version
  NS_VERSION_NAME  AUTO, or a version such as 1.2.0 (only for Exact version)
  NS_BUILD_NUMBER  AUTO, or a positive integer (the Android versionCode)
  NS_PLAY_TRACK    none, internal or alpha (where the job uploads the AAB)

The current version is the highest TestFlight version in App Store Connect
(iOS) and Google Play (every release name on every track). The release type
decides the next version from it; see codemagic_release_version.py.
AUTO build number is the highest versionCode of in.beyondrep.app in Google
Play (every track and every uploaded bundle) plus one. A manual build number
must be higher than that, so a run fails here instead of at upload.

Google Play is read with the Codemagic `google-play` CLI and the service
account JSON in GOOGLE_PLAY_SERVICE_ACCOUNT_CREDENTIALS (Codemagic group
ns_google_play); this script never prints it. Google Play is required except
for the very first build: only a manual build number with NS_PLAY_TRACK=none
may go on when the credentials are missing or a Play lookup (version or build
number) fails. That AAB is uploaded by hand in Play Console because Google
Play only accepts API uploads after that.

The Wear OS build uploaded by the same job shares the package and gets the next
versionCode, BEYONDREP_BUILD_NUMBER + 1. "Latest in Play" covers every uploaded
bundle, phone or watch, so the next phone build is always above the last watch
build.

The result is appended to $CM_ENV as BEYONDREP_VERSION_NAME,
BEYONDREP_BUILD_NUMBER and BEYONDREP_WATCH_BUILD_NUMBER for later build steps.
"""
import os
from pathlib import Path
import re
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from codemagic_release_version import (  # noqa: E402
    AUTO,
    CREDENTIALS,
    PACKAGE_NAME,
    ResolveError,
    current_version,
    format_version,
    next_version,
)

# Positive integer, no leading zero (a valid Android versionCode).
BUILD_NUMBER = re.compile(r"[1-9][0-9]{0,9}\Z")
TRACKS = ("none", "internal", "alpha")
# Google Play's largest allowed versionCode.
MAX_VERSION_CODE = 2_100_000_000


def latest_play_build() -> int:
    try:
        result = subprocess.run(
            [
                "google-play", "get-latest-build-number",
                "--package-name", PACKAGE_NAME,
                "--include-uploaded-builds",
                "--credentials", f"@env:{CREDENTIALS}",
            ],
            capture_output=True, text=True, timeout=300,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise ResolveError(f"Google Play lookup failed: {error}")
    if result.returncode != 0:
        detail = result.stderr.strip().splitlines()[-1:] or [""]
        raise ResolveError(
            f"Google Play lookup failed (exit {result.returncode}): {detail[0]} "
            f"Check that the {PACKAGE_NAME} app exists in Play Console and the "
            "service account in ns_google_play has access to it."
        )
    latest = result.stdout.strip()
    if latest == "":
        return 0
    if not re.fullmatch(r"[0-9]+", latest):
        raise ResolveError(
            f"Google Play returned an unexpected build number: {latest!r}"
        )
    return int(latest)


def resolve_build(raw: str, track: str) -> str:
    value = raw.strip()
    if value != AUTO and not (
        BUILD_NUMBER.match(value) and int(value) <= MAX_VERSION_CODE
    ):
        raise ResolveError(
            f"Invalid build number {value!r}: use a whole number from 1 to "
            f"{MAX_VERSION_CODE} with no leading zero, or AUTO."
        )
    if not os.environ.get(CREDENTIALS, "").strip():
        if value == AUTO or track != "none":
            raise ResolveError(
                f"{CREDENTIALS} is not set. Add the Play service account to "
                "the ns_google_play group, or for the very first build enter "
                "a build number and choose play_track none."
            )
        print(
            "No Play credentials: not checking the build number against "
            "Google Play. Upload this first AAB by hand in Play Console."
        )
        return value
    try:
        latest = latest_play_build()
    except ResolveError as error:
        # A new Play app with no uploaded bundle yet may have nothing to read.
        # Only a manual first build that is not uploaded may go on without it.
        if value == AUTO or track != "none":
            raise
        print(f"{error} Going on: build {value} is not uploaded by this job.")
        return value
    if value == AUTO:
        return str(latest + 1)
    if int(value) <= latest:
        raise ResolveError(
            f"Build number {value} must be higher than the latest Google Play "
            f"build, {latest}. Use AUTO or a number above {latest}."
        )
    return value


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        print("usage: codemagic_android_version.py", file=sys.stderr)
        return 2
    track = os.environ.get("NS_PLAY_TRACK", "").strip()
    try:
        if track not in TRACKS:
            raise ResolveError(
                f"Invalid play_track {track!r}: use one of {', '.join(TRACKS)}."
            )
        release_type = os.environ.get("NS_RELEASE_TYPE", "").strip()
        raw_build = os.environ.get("NS_BUILD_NUMBER", "")
        first_build = raw_build.strip() != AUTO and track == "none"
        current = current_version(play_optional=first_build)
        new = next_version(release_type, os.environ.get("NS_VERSION_NAME", ""), current)
        version = format_version(new)
        build = resolve_build(raw_build, track)
        watch_build = int(build) + 1
        if watch_build > MAX_VERSION_CODE:
            raise ResolveError(
                f"Build number {build} leaves no room for the watch build "
                f"({watch_build} is above Google Play's limit of {MAX_VERSION_CODE})."
            )
    except ResolveError as error:
        print(f"Version check failed: {error}", file=sys.stderr)
        return 1
    with open(os.environ["CM_ENV"], "a", encoding="utf-8") as env_file:
        env_file.write(f"BEYONDREP_VERSION_NAME={version}\n")
        env_file.write(f"BEYONDREP_BUILD_NUMBER={build}\n")
        env_file.write(f"BEYONDREP_WATCH_BUILD_NUMBER={watch_build}\n")
    before = format_version(current) if current is not None else "none"
    print(
        f"Release type {release_type}: {before} -> {version}, build number {build}, "
        f"watch build number {watch_build}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
