"""Version parsing and release-type bump rules for the Codemagic version scripts.

A release type picks how the next version name follows the highest version
already published:
  Fix or optimisation      MAJOR.FEATURE.FIX -> MAJOR.FEATURE.FIX+1
  Feature                  MAJOR.FEATURE.FIX -> MAJOR.FEATURE+1.0
  Major                    MAJOR.FEATURE.FIX -> MAJOR+1.0.0
  Same version, new build  keep the current version
  Exact version            use NS_VERSION_NAME, which must not be lower

Versions are MAJOR.FEATURE.FIX. Inputs of one or two parts are padded with
zeros and the output always has three parts. With no current version the
base is 0.0.0. This module holds the shared primitives (ResolveError, AUTO,
VERSION_NAME, and the App Store Connect TestFlight and Google Play lookups)
and imports no other script. Authentication comes from the integrations' environment; no
credential value is read or printed here.
"""
import json
import os
import re
import subprocess
from typing import Iterable, Optional

AUTO = "AUTO"
# CFBundleShortVersionString: one to three period-separated integers.
VERSION_NAME = re.compile(r"(0|[1-9][0-9]{0,3})(\.(0|[1-9][0-9]{0,3})){0,2}\Z")

FIX = "Fix or optimisation"
FEATURE = "Feature"
MAJOR = "Major"
SAME = "Same version, new build"
EXACT = "Exact version"
RELEASE_TYPES = (FIX, FEATURE, MAJOR, SAME, EXACT)

Version = tuple[int, int, int]
MAX_PART = 9999

BUNDLE_ID = "in.beyondrep.app"
PACKAGE_NAME = "in.beyondrep.app"
CREDENTIALS = "GOOGLE_PLAY_SERVICE_ACCOUNT_CREDENTIALS"


class ResolveError(Exception):
    pass


def asc(*args: str) -> str:
    try:
        result = subprocess.run(
            ["app-store-connect", *args],
            capture_output=True, text=True, timeout=300,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise ResolveError(f"App Store Connect lookup failed: {error}")
    if result.returncode != 0:
        detail = result.stderr.strip().splitlines()[-1:] or [""]
        raise ResolveError(
            f"App Store Connect lookup failed (exit {result.returncode}): "
            f"{detail[0]} Check the 'Codemagic Signing' integration, or that "
            "codemagic-cli-tools is 0.69 or newer (needs --all-versions)."
        )
    return result.stdout.strip()


def app_store_app_id() -> str:
    try:
        apps = json.loads(asc(
            "apps", "list", "--bundle-id-identifier", BUNDLE_ID,
            "--strict-match-identifier", "--json",
        ))
        return str(apps[0]["id"])
    except (ValueError, LookupError, TypeError):
        raise ResolveError(f"No App Store Connect app found for {BUNDLE_ID}.")


def _asc_json_list(*args: str) -> list:
    try:
        items = json.loads(asc(*args))
    except ValueError:
        raise ResolveError(f"App Store Connect returned invalid JSON for {args[1]}.")
    if not isinstance(items, list):
        raise ResolveError(f"App Store Connect returned unexpected JSON for {args[1]}.")
    return items


def _collect(texts: Iterable[object]) -> list[Version]:
    found = []
    for text in texts:
        if isinstance(text, str):
            parsed = parse_version(text)
            if parsed is not None:
                found.append(parsed)
    return found


def asc_versions() -> list[Version]:
    """TestFlight versions only. Every App Store build is first a TestFlight
    build, and the App Store version list holds an auto-created "1.0"
    placeholder that would wrongly make the current version 1.0.0."""
    app_id = app_store_app_id()
    texts = []
    for item in _asc_json_list("apps", "pre-release-versions", app_id, "--json"):
        attributes = item.get("attributes") if isinstance(item, dict) else None
        if isinstance(attributes, dict) and attributes.get("platform") == "IOS":
            texts.append(attributes.get("version"))
    return _collect(texts)


def play_versions() -> list[Version]:
    try:
        result = subprocess.run(
            [
                "google-play", "tracks", "list",
                "--package-name", PACKAGE_NAME,
                "--credentials", f"@env:{CREDENTIALS}",
                "--json",
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
    try:
        tracks = json.loads(result.stdout)
    except ValueError:
        raise ResolveError("Google Play returned invalid JSON for the track list.")
    if not isinstance(tracks, list):
        raise ResolveError("Google Play returned unexpected JSON for the track list.")
    texts = []
    for item in tracks:
        # codemagic-cli-tools wraps each Track as {"track": {"track": ..., ...}}.
        track = item.get("track") if isinstance(item, dict) else None
        if isinstance(track, dict):
            item = track
        releases = item.get("releases") if isinstance(item, dict) else None
        for release in releases if isinstance(releases, list) else []:
            if isinstance(release, dict):
                texts.append(release.get("name"))
    # A one-part name such as "3" is a release label, not a version.
    return _collect(
        t for t in texts if isinstance(t, str) and len(t.strip().split(".")) >= 2
    )


def current_version(*, play_optional: bool) -> Optional[Version]:
    found = asc_versions()
    if not os.environ.get(CREDENTIALS, "").strip():
        print(
            f"Google Play not checked: {CREDENTIALS} is not set. "
            "Using App Store Connect only."
        )
    else:
        try:
            found += play_versions()
        except ResolveError as error:
            if not play_optional:
                raise
            print(f"Google Play not checked: {error} Using App Store Connect only.")
    return highest(found)


def parse_version(text: str) -> Optional[Version]:
    value = text.strip()
    if not VERSION_NAME.match(value):
        return None
    parts = [int(part) for part in value.split(".")]
    parts += [0] * (3 - len(parts))
    return (parts[0], parts[1], parts[2])


def format_version(v: Version) -> str:
    return f"{v[0]}.{v[1]}.{v[2]}"


def highest(versions: Iterable[Version]) -> Optional[Version]:
    return max(versions, default=None)


def _checked(v: Version) -> Version:
    if max(v) > MAX_PART:
        raise ResolveError(
            f"Version {format_version(v)} is too large: each part must be "
            f"at most {MAX_PART}."
        )
    return v


def next_version(
    release_type: str, version_name: str, current: Optional[Version]
) -> Version:
    if release_type not in RELEASE_TYPES:
        raise ResolveError(
            f"Unknown release type {release_type!r}: use one of "
            + ", ".join(RELEASE_TYPES) + "."
        )
    name = version_name.strip()
    if release_type != EXACT:
        if name != AUTO:
            raise ResolveError(
                f"Version name {name!r} is only used with release type "
                f"{EXACT!r}. Set it to AUTO or choose {EXACT!r}."
            )
    elif name == AUTO:
        raise ResolveError(
            f"Release type {EXACT!r} needs a version name such as 1.2.0, not AUTO."
        )
    base = current if current is not None else (0, 0, 0)
    major, feature, fix = base
    if release_type == FIX:
        return _checked((major, feature, fix + 1))
    if release_type == FEATURE:
        return _checked((major, feature + 1, 0))
    if release_type == MAJOR:
        return _checked((major + 1, 0, 0))
    if release_type == SAME:
        if current is None:
            raise ResolveError(
                f"Release type {SAME!r} needs an existing version, but there is "
                "no version in a store yet."
            )
        return current
    exact = parse_version(name)
    if exact is None:
        raise ResolveError(
            f"Invalid version name {name!r}: use one to three numbers "
            "separated by dots, such as 1.2.0."
        )
    if current is not None and exact < current:
        raise ResolveError(
            f"Version {format_version(exact)} is lower than the current "
            f"version {format_version(current)}. Use that version or higher."
        )
    return exact
