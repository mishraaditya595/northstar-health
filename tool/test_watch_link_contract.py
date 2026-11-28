"""Watch link contract checks (phone <-> watch messages); run from repository root.

Dependencies: python3 -m pip install -r tool/requirements-ci.txt
"""

import json
import unittest
from datetime import datetime
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


def _parse_utc(text):
    return datetime.fromisoformat(text.replace("Z", "+00:00"))


def reference_session_state(case):
    """Independent reference of the session_state builder rules (README)."""
    events, ctx = case["events"], case["context"]
    template, unit = ctx["template"], ctx["unit"]
    seen, ordered = set(), []
    for event in events:
        if event["event_id"] not in seen:
            seen.add(event["event_id"])
            ordered.append(event)
    ordered.sort(key=lambda e: e["sequence"])
    replay = reference_replay(ordered)
    started = next(e for e in ordered if e["type"] == "workout_started")
    status = {"active": "active", "paused": "paused"}.get(replay["status"], "ended")
    body = {
        "session_id": started["session_id"],
        "owner": started["payload"]["owner"],
        "status": status,
        "name": started["payload"]["name"],
        "started_at_utc": started["occurred_at_utc"],
        "last_sequence": max(e["sequence"] for e in ordered),
    }
    if status == "ended":
        body["end_reason"] = (
            "completed" if replay["status"] == "completed" else "discarded"
        )
    # Pauses: an interval ends at the next resume, completion or discard.
    paused_total, paused_since = 0, None
    for e in ordered:
        if e["type"] == "workout_paused" and paused_since is None:
            paused_since = e["occurred_at_utc"]
        elif (
            e["type"] in ("workout_resumed", "workout_completed", "workout_abandoned")
            and paused_since is not None
        ):
            paused_total += int(
                (_parse_utc(e["occurred_at_utc"]) - _parse_utc(paused_since)).total_seconds()
            )
            paused_since = None
    if status == "paused":
        body["paused_at_utc"] = paused_since
    if paused_total > 0:
        body["paused_seconds"] = paused_total
    # Rest: the last rest_started, ended by clear, log, pause, complete, discard.
    deadline = None
    for e in ordered:
        if e["type"] == "rest_started":
            deadline = e["payload"]["deadline_utc"]
        elif e["type"] in (
            "rest_cleared",
            "set_logged",
            "workout_paused",
            "workout_completed",
            "workout_abandoned",
        ):
            deadline = None
    if deadline:
        body["rest_deadline_utc"] = deadline
    done = {s["set_id"]: s for s in replay["sets"]}
    units, kinds = {}, {}
    for e in ordered:
        if e["type"] in ("set_logged", "set_corrected"):
            units[e["payload"]["set_id"]] = e["payload"]["input_unit"]
            kinds[e["payload"]["set_id"]] = e["payload"]["kind"]
    exercises, current = [], None
    for ex in sorted(template["exercises"], key=lambda x: x["position"]):
        sets = []
        for st in sorted(ex["sets"], key=lambda x: x["position"]):
            item = {"set_id": st["set_id"], "position": st["position"]}
            d = done.get(st["set_id"])
            if d is None:
                item.update(kind=st["kind"], status="planned", input_unit=unit)
                for src, dst in (
                    ("target_reps", "reps"),
                    ("target_seconds", "duration_seconds"),
                    ("target_load_grams", "load_grams"),
                ):
                    if st.get(src):
                        item[dst] = st[src]
                if 1 <= (st.get("rest_seconds") or 0) <= 3600:
                    item["rest_seconds"] = st["rest_seconds"]
                if current is None and status != "ended":
                    current = st["set_id"]
            elif d["status"] == "skipped":
                item.update(kind=st["kind"], status="skipped")
            else:
                item.update(
                    kind=kinds[st["set_id"]],
                    status="completed",
                    input_unit=units.get(st["set_id"], unit),
                )
                for k in ("reps", "duration_seconds", "load_grams", "rpe"):
                    if k == "load_grams" and not d.get(k):
                        continue
                    if k in d:
                        item[k] = d[k]
            sets.append(item)
        exercises.append(
            {"exercise_id": ex["exercise_id"], "name": ex["name"], "kind": ex["kind"], "sets": sets}
        )
    if current:
        body["current_set_id"] = current
    body["exercises"] = exercises
    if ctx.get("applied_command_ids"):
        body["applied_command_ids"] = ctx["applied_command_ids"][-20:]
    if ctx.get("rejected_commands"):
        body["rejected_commands"] = ctx["rejected_commands"][-20:]
    return {
        "schema_version": 1,
        "message_id": ctx["message_id"],
        "type": "session_state",
        "sent_at_utc": ctx["sent_at_utc"],
        "account_key": ctx["account_key"],
        "body": body,
    }


def workout_health_errors(body):
    """workout_health: end after start, samples inside it, strictly increasing."""
    errors = []
    start, end = _parse_utc(body["start_utc"]), _parse_utc(body["end_utc"])
    if end <= start:
        errors.append("end_utc not after start_utc")
    times = [_parse_utc(s["at_utc"]) for s in body.get("heart_rate", [])]
    if any(t < start or t > end for t in times):
        errors.append("heart rate sample outside the workout")
    if any(a >= b for a, b in zip(times, times[1:])):
        errors.append("heart rate samples not strictly increasing")
    return errors


def cross_field_errors(message):
    """Rules JSON Schema cannot express (see the contract README)."""
    if message.get("type") == "workout_health":
        return workout_health_errors(message["body"])
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
            "health_snapshot_week_after_local_date",
            "health_snapshot_factor_status_too_long",
            "health_snapshot_usual_negative",
            "workout_link_missing_uuid",
            "workout_link_extra_field",
            "workout_link_bad_uuid",
            "join_extra_field",
            "workout_health_bpm_zero",
            "workout_health_sample_outside",
            "workout_health_unsorted",
            "workout_health_extra_field",
            "ack_not_written_stored",
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

    def test_stage_5b_messages_have_valid_fixtures(self):
        types = {
            load(p)["type"] for p in (LINK / "fixtures/valid").glob("*.json")
        }
        self.assertIn("workout_link", types)
        self.assertIn("join", types)
        phone = load(LINK / "fixtures/valid/session_state_phone.json")
        self.assertEqual(phone["body"]["owner"], "phone")
        self.assertEqual(list(self.validator.iter_errors(phone)), [])

    def test_health_values_only_in_two_messages(self):
        words = ("sleep", "hrv", "steps", "heart_rate", "resting_hr", "kcal")
        for path in (LINK / "fixtures/valid").glob("*.json"):
            text = json.dumps(load(path)).lower()
            has = any(w in text for w in words)
            allowed = path.stem.startswith(("health_snapshot", "workout_health"))
            with self.subTest(file=path.name):
                self.assertEqual(has, allowed)

    def test_workout_health_invalid_fixtures_fail_for_their_reason(self):
        invalid = LINK / "fixtures/invalid"
        schema_failures = (
            "workout_health_bpm_zero",
            "workout_health_extra_field",
            "ack_not_written_stored",
        )
        for name in schema_failures:
            with self.subTest(file=name):
                data = load(invalid / (name + ".json"))
                self.assertTrue(list(self.validator.iter_errors(data)))
        for name, reason in (
            ("workout_health_sample_outside", "heart rate sample outside the workout"),
            ("workout_health_unsorted", "heart rate samples not strictly increasing"),
        ):
            with self.subTest(file=name):
                data = load(invalid / (name + ".json"))
                # Schema-valid: only the cross-field rule catches them.
                self.assertEqual(list(self.validator.iter_errors(data)), [])
                self.assertEqual(cross_field_errors(data), [reason])

    def test_not_written_only_with_rejected(self):
        data = load(LINK / "fixtures/valid/ack_not_written.json")
        self.assertEqual(list(self.validator.iter_errors(data)), [])
        for result in ("stored", "duplicate"):
            data["body"]["result"] = result
            self.assertTrue(list(self.validator.iter_errors(data)), result)

    def test_workout_health_bounds(self):
        base = load(LINK / "fixtures/valid/workout_health.json")
        for key, value in (("total_kcal", 0), ("total_kcal", 10001)):
            data = json.loads(json.dumps(base))
            data["body"][key] = value
            with self.subTest(key=key, value=value):
                self.assertTrue(list(self.validator.iter_errors(data)))
        for bpm in (24, 251, 70.5):
            data = json.loads(json.dumps(base))
            data["body"]["heart_rate"][0]["bpm"] = bpm
            with self.subTest(bpm=bpm):
                self.assertTrue(list(self.validator.iter_errors(data)))
        data = json.loads(json.dumps(base))
        data["body"]["heart_rate"] = [
            {"at_utc": "2026-10-23T11:00:00Z", "bpm": 70}
        ] * 601
        self.assertTrue(list(self.validator.iter_errors(data)))
        data = json.loads(json.dumps(base))
        data["body"]["end_utc"] = data["body"]["start_utc"]
        self.assertEqual(cross_field_errors(data)[0], "end_utc not after start_utc")

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

    def test_completed_cases_validate_against_schema(self):
        cases = sorted((LINK / "cases/completed").glob("*.json"))
        self.assertGreaterEqual(len(cases), 2)
        for path in cases:
            case = load(path)
            with self.subTest(file=path.name):
                for event in case["events"]:
                    self.v2.validate(event)
                self.validator.validate(case["expected"])
                self.assertEqual(case["expected"]["type"], "completed_workout")
                self.assertEqual(
                    case["expected"]["body"]["last_sequence"],
                    max(e["sequence"] for e in case["events"]),
                )

    def test_session_state_cases(self):
        cases = sorted((LINK / "cases/session_state").glob("*.json"))
        self.assertGreaterEqual(len(cases), 4)
        for path in cases:
            case = load(path)
            with self.subTest(file=path.name):
                for event in case["events"]:
                    self.v2.validate(event)
                self.validator.validate(case["expected"])
                self.assertEqual(reference_session_state(case), case["expected"])


if __name__ == "__main__":
    unittest.main()
