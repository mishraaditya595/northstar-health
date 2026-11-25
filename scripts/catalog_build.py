"""Assemble, canonicalize and hash the training catalogue; generate migrations."""
import hashlib
import json
from pathlib import Path

PROVENANCE = {
    "source": "BeyondRep original",
    "license": "MPL-2.0",
    "attribution": "",
}


def _read_arrays(directory):
    items = []
    if directory.is_dir():
        for path in sorted(directory.glob("*.json")):
            data = json.loads(path.read_text(encoding="utf-8"))
            if not isinstance(data, list):
                raise ValueError(f"{path}: expected a JSON array")
            items.extend(data)
    return sorted(items, key=lambda item: item["id"])


def assemble(root, release, published_at, schema_version=1, min_app_schema=1):
    root = Path(root)
    return {
        "schemaVersion": schema_version,
        "minAppCatalogSchema": min_app_schema,
        "release": release,
        "publishedAt": published_at,
        "provenance": dict(PROVENANCE),
        "exercises": _read_arrays(root / "exercises"),
        "templates": _read_arrays(root / "templates"),
        "programs": _read_arrays(root / "programs"),
    }


def canonical_bytes(snapshot):
    return json.dumps(
        snapshot, sort_keys=True, separators=(",", ":"), ensure_ascii=False
    ).encode("utf-8")


def digest(snapshot):
    raw = canonical_bytes(snapshot)
    return hashlib.sha256(raw).hexdigest(), len(raw)


def load_lock(path):
    path = Path(path)
    if not path.exists():
        return {"releases": []}
    return json.loads(path.read_text(encoding="utf-8"))


def lock_entry(snapshot, sha256):
    return {
        "release": snapshot["release"],
        "sha256": sha256,
        "exercises": {e["id"]: e["mode"] for e in snapshot["exercises"]},
        "retired": sorted(
            e["id"] for e in snapshot["exercises"] if e["status"] == "retired"
        ),
        "templates": [t["id"] for t in snapshot["templates"]],
        "programs": [p["id"] for p in snapshot["programs"]],
    }
