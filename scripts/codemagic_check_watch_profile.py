#!/usr/bin/env python3
"""Fails the iOS build early when signing has no profile for the watch app.

`xcode-project use-profiles` writes the export options plist with one
provisioning profile per signed bundle ID. If the watch App ID is missing,
the archive would fail late and unclearly, so check it right after.
"""
import plistlib
import sys

REQUIRED = ("in.beyondrep.app", "in.beyondrep.app.watchkitapp")
FALLBACK = (
    "Upload an App Store profile for each bundle ID to Codemagic and list both "
    "profiles in the job; see the 'Apple Watch app' fallback in "
    "docs/IOS_TESTFLIGHT_CODEMAGIC.md."
)


def main(argv):
    if len(argv) != 2:
        print("usage: codemagic_check_watch_profile.py EXPORT_OPTIONS_PLIST", file=sys.stderr)
        return 2
    try:
        with open(argv[1], "rb") as handle:
            options = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException) as error:
        print(f"Cannot read the export options plist: {error}", file=sys.stderr)
        return 2
    profiles = options.get("provisioningProfiles") or {}
    missing = [bundle for bundle in REQUIRED if bundle not in profiles]
    if missing:
        print(f"No signing profile for {', '.join(missing)}. {FALLBACK}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
