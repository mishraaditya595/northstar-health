"""Validate one assembled catalogue snapshot against the schema and the lock."""
import json
import re
from pathlib import Path

from jsonschema import Draft202012Validator

SCHEMA_PATH = (
    Path(__file__).resolve().parent.parent / "catalog" / "schema" / "catalog.schema.json"
)

MUSCLES = frozenset(
    "chest shoulders biceps forearms abs obliques quads calves traps lats "
    "lowerBack triceps glutes hamstrings".split()
)
MUSCLE_GROUPS = frozenset("Chest Back Legs Shoulders Arms Core".split())
MODES = frozenset(["reps_load", "reps", "duration", "duration_load"])
EQUIPMENT = frozenset(
    "barbell dumbbell kettlebell machine cable band bodyweight bench "
    "pull_up_bar ez_bar trap_bar plate box rings other".split()
)
CATEGORIES = frozenset(
    "squat hinge lunge push_horizontal push_vertical pull_horizontal "
    "pull_vertical carry core isolation calf conditioning mobility".split()
)
EMPTY_LOCK = {"releases": []}

_DURATION_MODES = frozenset(["duration", "duration_load"])
_SLUG = r"[a-z0-9]+(-[a-z0-9]+)*"
_ID_PATTERNS = {
    "exercise": re.compile(rf"^builtin\.v1\.{_SLUG}$"),
    "template": re.compile(rf"^tpl\.{_SLUG}$"),
    "program": re.compile(rf"^prog\.{_SLUG}$"),
}


def _floats(node, path="$"):
    if isinstance(node, float):
        yield path
    elif isinstance(node, dict):
        for key, value in node.items():
            yield from _floats(value, f"{path}.{key}")
    elif isinstance(node, list):
        for i, value in enumerate(node):
            yield from _floats(value, f"{path}[{i}]")


def _in_range(value, low, high):
    return isinstance(value, int) and low <= value <= high


def _check_prescription(owner, item, modes, errors):
    ex_id = item["exerciseId"]
    label = f"{owner} exercise {ex_id}"
    if ex_id not in modes:
        errors.append(f"{label}: unknown exercise reference")
        return
    if not _in_range(item["sets"], 1, 30):
        errors.append(f"{label}: sets must be 1 to 30")
    if not _in_range(item["restSeconds"], 0, 3600):
        errors.append(f"{label}: restSeconds must be 0 to 3600")
    has_reps = "repsMin" in item or "repsMax" in item
    has_duration = "durationSeconds" in item
    if has_reps and has_duration:
        errors.append(f"{label}: both reps and duration given")
    elif modes[ex_id] in _DURATION_MODES:
        if has_reps or not has_duration:
            errors.append(f"{label}: timed exercise needs durationSeconds and no reps")
    elif has_duration or not ("repsMin" in item and "repsMax" in item):
        errors.append(f"{label}: rep exercise needs repsMin and repsMax and no duration")
    if has_duration and not _in_range(item["durationSeconds"], 1, 3600):
        errors.append(f"{label}: durationSeconds must be 1 to 3600")
    if "repsMin" in item and "repsMax" in item:
        low, high = item["repsMin"], item["repsMax"]
        if not (_in_range(low, 1, 1000) and _in_range(high, 1, 1000)):
            errors.append(f"{label}: reps must be 1 to 1000")
        elif low > high:
            errors.append(f"{label}: repsMin greater than repsMax")


def _check_lock(snapshot, kinds, modes, lock, errors):
    releases = lock.get("releases", [])
    if releases and snapshot["release"] <= max(r["release"] for r in releases):
        errors.append(
            f"release {snapshot['release']} must exceed the highest locked release"
        )
    locked_kind = {}
    locked_mode = {}
    retired = set()
    for entry in releases:
        for ex_id, mode in entry.get("exercises", {}).items():
            locked_kind[ex_id] = "exercise"
            locked_mode[ex_id] = mode
        for t_id in entry.get("templates", []):
            locked_kind[t_id] = "template"
        for p_id in entry.get("programs", []):
            locked_kind[p_id] = "program"
        retired.update(entry.get("retired", []))
    for item_id, kind in sorted(locked_kind.items()):
        if item_id not in kinds:
            errors.append(f"{item_id}: removed since an earlier release (retire it instead)")
        elif kinds[item_id] != kind:
            errors.append(f"{item_id}: kind changed from {kind} to {kinds[item_id]}")
    for ex_id, mode in sorted(locked_mode.items()):
        if ex_id in modes and modes[ex_id] != mode:
            errors.append(
                f"{ex_id}: mode changed from {mode} to {modes[ex_id]}; use a new id"
            )
    for ex_id in sorted(retired):
        if kinds.get(ex_id) == "exercise" and snapshot_status(snapshot, ex_id) != "retired":
            errors.append(f"{ex_id}: retired id reused as active")


def snapshot_status(snapshot, ex_id):
    for ex in snapshot["exercises"]:
        if ex["id"] == ex_id:
            return ex["status"]
    return None


def validate_snapshot(snapshot, lock):
    """Return human-readable errors; an empty list means valid."""
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    schema_errors = sorted(
        Draft202012Validator(schema).iter_errors(snapshot),
        key=lambda e: list(map(str, e.absolute_path)),
    )
    if schema_errors:
        return [
            "schema: "
            + (".".join(map(str, e.absolute_path)) or "$")
            + ": "
            + e.message[:200]
            for e in schema_errors
        ]

    errors = [f"float value at {p}; use integers only" for p in _floats(snapshot)]

    kinds = {}
    for kind, key in (("exercise", "exercises"), ("template", "templates"), ("program", "programs")):
        for item in snapshot[key]:
            item_id = item["id"]
            if not _ID_PATTERNS[kind].match(item_id):
                errors.append(f"{item_id}: bad {kind} id")
            if item_id in kinds:
                errors.append(f"duplicate id {item_id}")
            kinds[item_id] = kind

    modes = {ex["id"]: ex["mode"] for ex in snapshot["exercises"]}
    retired = {ex["id"] for ex in snapshot["exercises"] if ex["status"] == "retired"}
    templates = {t["id"] for t in snapshot["templates"]}

    for template in snapshot["templates"]:
        for item in template["exercises"]:
            if item["exerciseId"] in retired:
                errors.append(
                    f"template {template['id']}: references retired exercise "
                    f"{item['exerciseId']}"
                )
            _check_prescription(f"template {template['id']}", item, modes, errors)

    for program in snapshot["programs"]:
        pid = program["id"]
        week = program["week"]
        if len(week) != 7:
            errors.append(f"program {pid}: week must have exactly 7 entries")
            continue
        trained = [d for d in week if d is not None]
        if not trained:
            errors.append(f"program {pid}: needs at least one training day")
        if program["daysPerWeek"] != len(trained):
            errors.append(
                f"program {pid}: daysPerWeek {program['daysPerWeek']} does not match "
                f"{len(trained)} training days"
            )
        for day in trained:
            if day not in templates:
                errors.append(f"program {pid}: unknown template reference {day}")

    _check_lock(snapshot, kinds, modes, lock, errors)
    return errors
