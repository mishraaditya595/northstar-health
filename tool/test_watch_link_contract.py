"""Watch link contract checks (phone <-> watch messages); run from repository root.

Dependencies: python3 -m pip install -r tool/requirements-ci.txt
"""

import json
import unittest
from pathlib import Path

from jsonschema import Draft202012Validator
from referencing import Registry, Resource

try:
    from contract_validation import ContractValidator, format_checker
except ImportError:  # run as `python3 -m unittest tool.<module>` from the root
    from tool.contract_validation import ContractValidator, format_checker

ROOT = Path(__file__).resolve().parents[1]
LINK = ROOT / "contracts" / "watch_link" / "v1"
V2 = ROOT / "contracts" / "workout_sync" / "v2"
BASE = "https://contracts.beyondrep.invalid/"


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def reference_replay(events):
    """Independent reference of the replay rules in the case README."""
    seen, ordered = set(), []
    for event in events:
        if event["event_id"] not in seen:
            seen.add(event["event_id"])
            ordered.append(event)
    ordered.sort(key=lambda e: e["sequence"])
    present = {e["sequence"] for e in ordered}
    gaps = [n for n in range(max(present) + 1) if n not in present] if present else []
    status, sets = "active", {}
    for e in ordered:
        t, p = e["type"], e["payload"]
        if t == "workout_paused":
            status = "paused"
        elif t == "workout_resumed":
            status = "active"
        elif t == "workout_completed":
            status = "completed"
        elif t == "workout_abandoned":
            status = "abandoned"
        elif t in ("set_logged", "set_corrected"):
            s = sets.setdefault(p["set_id"], {"history": []})
            s.update(status="completed", kind=p["kind"])
            for k in ("reps", "duration_seconds", "load_grams", "rpe"):
                s.pop(k, None)
                if k in p:
                    s[k] = p[k]
            s["history"].append(e["event_id"])
        elif t == "set_skipped":
            s = sets.setdefault(p["set_id"], {"history": [], "kind": "working"})
            for k in ("reps", "duration_seconds", "load_grams", "rpe"):
                s.pop(k, None)
            s["status"] = "skipped"
            s["history"].append(e["event_id"])
    out, volume, done = [], 0, 0
    for set_id, s in sets.items():
        out.append({"set_id": set_id, **{k: v for k, v in s.items() if k != "kind"}})
        if s["status"] == "completed" and s["kind"] == "working":
            done += 1
            if "reps" in s and s.get("load_grams"):
                volume += s["reps"] * s["load_grams"]
    return {
        "status": status,
        "sets": out,
        "volume_grams": volume,
        "completed_sets": done,
        "gaps": gaps,
    }


def cross_field_errors(message):
    """Rules JSON Schema cannot express (see the contract README)."""
    if message.get("type") != "health_snapshot":
        return []
    body, errors = message["body"], []
    inputs = [f["input"] for f in body.get("readiness", {}).get("factors", [])]
    if len(inputs) != len(set(inputs)):
        errors.append("duplicate readiness factor input")
    dates = [d["local_date"] for d in body.get("week", [])]
    if any(a >= b for a, b in zip(dates, dates[1:])):
        errors.append("week local_date not strictly ascending")
    if dates and dates[-1] > body["local_date"]:
        errors.append("week ends after local_date")
    return errors


class WatchLinkContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        schema = load(LINK / "message.schema.json")
        Draft202012Validator.check_schema(schema)
        registry = Registry().with_resource(
            BASE + "contracts/workout_sync/v2/envelope.schema.json",
            Resource.from_contents(load(V2 / "envelope.schema.json")),
        )
        cls.validator = ContractValidator(
            schema, format_checker=format_checker(), registry=registry
        )
        cls.v2 = ContractValidator(
            load(V2 / "envelope.schema.json"), format_checker=format_checker()
        )

    def test_valid_messages(self):
        fixtures = sorted((LINK / "fixtures/valid").glob("*.json"))
        self.assertGreaterEqual(len(fixtures), 10)
        for path in fixtures:
            with self.subTest(file=path.name):
                self.validator.validate(load(path))
                self.assertEqual(cross_field_errors(load(path)), [])

    def test_invalid_messages(self):
        fixtures = sorted((LINK / "fixtures/invalid").glob("*.json"))
        self.assertGreaterEqual(len(fixtures), 20)
        names = {p.stem for p in fixtures}
        for expected in (
            "missing_account_key",
            "bad_local_date",
            "readiness_band_unknown",
            "completed_workout_wrong_origin",
            "negative_steps",
            "command_unknown",
            "ack_bad_result",
            "event_v1_inside",
            "health_snapshot_factor_unknown_input",
            "health_snapshot_factor_duplicate",
            "health_snapshot_week_out_of_order",
            "health_snapshot_week_eight_days",
            "health_snapshot_factor_status_too_long",
            "health_snapshot_usual_negative",
        ):
            self.assertIn(expected, names)
        for path in fixtures:
            with self.subTest(file=path.name):
                data = load(path)
                self.assertTrue(
                    list(self.validator.iter_errors(data))
                    or cross_field_errors(data),
                    path.name,
                )

    def test_completed_set_cannot_have_reps_and_duration(self):
        data = load(LINK / "fixtures/valid/completed_workout.json")
        data["body"]["workout"]["exercises"][0]["sets"][0]["duration_seconds"] = 30
        self.assertTrue(list(self.validator.iter_errors(data)))

    def test_health_values_only_in_health_snapshot(self):
        words = ("sleep", "hrv", "steps", "heart_rate", "resting_hr")
        for path in (LINK / "fixtures/valid").glob("*.json"):
            text = json.dumps(load(path)).lower()
            has = any(w in text for w in words)
            with self.subTest(file=path.name):
                self.assertEqual(has, path.stem.startswith("health_snapshot"))

    def test_replay_cases(self):
        cases = sorted((LINK / "cases/replay").glob("*.json"))
        names = {p.stem for p in cases}
        for expected in (
            "basic_three_sets",
            "timed_set",
            "duplicate_event",
            "correction_chain",
            "out_of_order_sequence",
            "gap_in_sequence",
            "skip_then_log",
            "abandoned",
        ):
            self.assertIn(expected, names)
        for path in cases:
            case = load(path)
            with self.subTest(file=path.name):
                for event in case["events"]:
                    self.v2.validate(event)
                self.assertEqual(reference_replay(case["events"]), case["expected"])


if __name__ == "__main__":
    unittest.main()
