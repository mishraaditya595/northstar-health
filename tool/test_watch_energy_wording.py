"""The watch app never shows the word "readiness" in a user-visible string."""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIRS = [
    ROOT / "apps/watch_os/Sources",
    ROOT / "apps/watch_os/Packages/BeyondRepWatchCore/Sources",
]
# Wire keys of the unchanged watch_link contract: exactly the bare literal.
WIRE_KEY_FILES = {"WatchMessage.swift", "GlanceState.swift"}
LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')


def hits_in(path: Path, text: str):
    hits = []
    for number, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("//") or stripped.startswith("#Preview("):
            continue
        line = re.sub(r"\s//.*$", "", line)
        for match in LITERAL.finditer(line):
            value = match.group(1)
            if "readiness" not in value.lower():
                continue
            if value == "readiness" and path.name in WIRE_KEY_FILES:
                continue
            hits.append(f"{path}:{number}: {value}")
    return hits


class WatchEnergyWordingTest(unittest.TestCase):
    def test_no_readiness_in_watch_strings(self):
        hits = []
        for directory in DIRS:
            for path in sorted(directory.rglob("*.swift")):
                hits += hits_in(path, path.read_text(encoding="utf-8"))
        self.assertEqual(hits, [], "\n".join(hits))

    def test_checker_flags_user_text_and_exempts_wire_keys(self):
        flagged = hits_in(Path("Other.swift"), 'Text("Readiness 5")\nlet k = "readiness"')
        self.assertEqual(len(flagged), 2)
        wire = hits_in(Path("GlanceState.swift"), 'raw["readiness"]\nText("Opens readiness")')
        self.assertEqual(len(wire), 1)
        self.assertEqual(hits_in(Path("A.swift"), '#Preview("Readiness") {\n// "readiness"'), [])


if __name__ == "__main__":
    unittest.main()
