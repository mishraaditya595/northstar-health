"""Version parsing and release-type bump rules for the Codemagic version scripts.

A release type picks how the next version name follows the highest version
already published (or the pubspec version when nothing is published):
  Fix or optimisation      MAJOR.FEATURE.FIX -> MAJOR.FEATURE.FIX+1
  Feature                  MAJOR.FEATURE.FIX -> MAJOR.FEATURE+1.0
  Major                    MAJOR.FEATURE.FIX -> MAJOR+1.0.0
  Same version, new build  keep the current version
  Exact version            use NS_VERSION_NAME, which must not be lower

Versions are MAJOR.FEATURE.FIX. Inputs of one or two parts are padded with
zeros and the output always has three parts. With no current version the
base is 0.0.0. This module holds the shared primitives (ResolveError, AUTO,
VERSION_NAME) and imports no other script.
"""
import re
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


class ResolveError(Exception):
    pass


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
                "no version in the store or the pubspec yet."
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
