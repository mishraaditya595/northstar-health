#!/usr/bin/env python3
"""P2-08 hosted signed-JWT owner-isolation preflight (read-only).

Requires two REAL verified Supabase Auth sessions and an existing disposable,
completed phone workout fixture owned by each account. Never creates/deletes
users, records, migrations or Edge Functions. No secret values or response
bodies are printed. No service-role key may be used.
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
from dataclasses import dataclass
from typing import Any, Callable


class AuditFailure(Exception):
    pass


class _RejectRedirects(urllib.request.HTTPRedirectHandler):
    """Do not resend a bearer token or API key to any redirect destination."""

    def http_error_301(self, request, fp, code, message, headers):
        # Reject even malformed 3xx responses without a Location header.
        raise AuditFailure("unexpected_redirect")

    http_error_302 = http_error_301
    http_error_303 = http_error_301
    http_error_307 = http_error_301
    http_error_308 = http_error_301


@dataclass(frozen=True)
class Reply:
    status: int
    data: Any


def _require(condition: bool, code: str) -> None:
    if not condition:
        raise AuditFailure(code)


def _uuid(value: str, label: str) -> str:
    try:
        parsed = uuid.UUID(value)
        _require(str(parsed) == value.lower(), label + "_invalid")
        return str(parsed)
    except (ValueError, AttributeError, TypeError):
        raise AuditFailure(label + "_invalid") from None


def _requester(url: str, key: str) -> Callable[..., Reply]:
    base = url.rstrip("/")
    parsed = urllib.parse.urlparse(base)
    _require(parsed.scheme == "https" and bool(parsed.netloc)
             and not parsed.username and not parsed.password
             and not parsed.query and not parsed.fragment,
             "hosted_https_url_required")
    # A fresh opener with explicit redirect rejection; urllib's default
    # redirect handler is unsafe for requests carrying credentials.
    opener = urllib.request.build_opener(_RejectRedirects())

    def call(method: str, path: str, token: str | None = None,
             query: dict[str, str] | None = None,
             payload: dict[str, Any] | None = None) -> Reply:
        target = base + path
        if query:
            target += "?" + urllib.parse.urlencode(query)
        headers = {"apikey": key, "Accept": "application/json"}
        if token:
            headers["Authorization"] = "Bearer " + token
        body = None
        if payload is not None:
            headers["Content-Type"] = "application/json"
            body = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(target, data=body, headers=headers,
                                     method=method)
        try:
            with opener.open(req, timeout=20) as response:
                return Reply(response.status, json.loads(
                    response.read(2 * 1024 * 1024).decode("utf-8")))
        except urllib.error.HTTPError as error:
            # Deliberately do not read/echo server error bodies: they may
            # include personal identifiers or authorization metadata.
            return Reply(error.code, None)
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError,
                UnicodeDecodeError, ValueError):
            raise AuditFailure("network_or_invalid_response") from None
    return call


def run_audit(call: Callable[..., Reply], token_a: str, token_b: str,
              workout_a: str, workout_b: str) -> list[str]:
    """Fail closed on missing fixtures: an empty project cannot prove RLS."""
    _require(bool(token_a) and bool(token_b) and token_a != token_b,
             "two_distinct_sessions_required")
    workout_a = _uuid(workout_a, "fixture_a")
    workout_b = _uuid(workout_b, "fixture_b")
    _require(workout_a != workout_b, "distinct_workouts_required")
    passed: list[str] = []
    accounts: list[str] = []

    for name, token in (("a", token_a), ("b", token_b)):
        result = call("GET", "/auth/v1/user", token)
        _require(result.status == 200 and isinstance(result.data, dict),
                 name + "_jwt_not_verified")
        user = result.data
        owner = _uuid(user.get("id"), name + "_owner")
        _require(user.get("is_anonymous") is False,
                 name + "_anonymous_not_permitted")
        accounts.append(owner)
        passed.append(name + "_signed_verified_identity")
    _require(accounts[0] != accounts[1], "two_distinct_owners_required")

    def records(token: str | None, owner: str, workout: str) -> Reply:
        return call("GET", "/rest/v1/workout_records", token, {
            "select": "user_id,workout_id,status,deleted_at,server_revision,"
                      "server_change_seq",
            "user_id": "eq." + owner,
            "workout_id": "eq." + workout,
        })

    for index, (token, workout) in enumerate(
            ((token_a, workout_a), (token_b, workout_b))):
        owner = accounts[index]
        response = records(token, owner, workout)
        _require(response.status == 200
                 and isinstance(response.data, list)
                 and len(response.data) == 1,
                 "own_completed_fixture_missing_" + str(index))
        row = response.data[0]
        _require(isinstance(row, dict)
                 and row.get("user_id") == owner
                 and row.get("workout_id") == workout
                 and row.get("status") == "completed"
                 and row.get("deleted_at") is None
                 and type(row.get("server_revision")) is int
                 and row["server_revision"] >= 1
                 and type(row.get("server_change_seq")) is int
                 and row["server_change_seq"] >= 1,
                 "own_fixture_invalid_" + str(index))
        passed.append("owner_" + str(index) + "_sees_completed_fixture")

    for index, (token, other_owner, other_workout) in enumerate((
            (token_a, accounts[1], workout_b),
            (token_b, accounts[0], workout_a))):
        response = records(token, other_owner, other_workout)
        _require(response.status == 200 and response.data == [],
                 "cross_owner_select_leak_" + str(index))
        passed.append("owner_" + str(index) + "_cannot_select_other")

    # Also challenge RLS with a workout UUID alone, without owner filtering.
    for index, (token, other_workout) in enumerate((
            (token_a, workout_b), (token_b, workout_a))):
        response = call("GET", "/rest/v1/workout_records", token, {
            "select": "workout_id", "workout_id": "eq." + other_workout,
        })
        _require(response.status == 200 and response.data == [],
                 "cross_owner_uuid_leak_" + str(index))
        passed.append("owner_" + str(index) + "_uuid_only_isolation")

    for index, (token, own, other) in enumerate((
            (token_a, workout_a, workout_b),
            (token_b, workout_b, workout_a))):
        own_reply = call("POST", "/rest/v1/rpc/get_workout_for_resolution",
                         token, payload={"p_workout_id": own})
        other_reply = call("POST", "/rest/v1/rpc/get_workout_for_resolution",
                           token, payload={"p_workout_id": other})
        _require(own_reply.status == 200
                 and isinstance(own_reply.data, dict)
                 and isinstance(own_reply.data.get("change"), dict)
                 and own_reply.data["change"].get("workout_id") == own,
                 "own_point_lookup_invalid_" + str(index))
        _require(other_reply.status == 200
                 and isinstance(other_reply.data, dict)
                 and other_reply.data.get("change") is None,
                 "cross_owner_point_lookup_leak_" + str(index))
        passed.append("owner_" + str(index) + "_point_lookup_isolation")

    for index, (token, own, other) in enumerate((
            (token_a, workout_a, workout_b),
            (token_b, workout_b, workout_a))):
        cursor = 0
        epoch: str | None = None
        observed: set[str] = set()
        for _ in range(100):
            body: dict[str, Any] = {"p_after_seq": cursor, "p_limit": 100}
            if epoch is not None:
                body["p_cursor_epoch"] = epoch
            reply = call("POST", "/rest/v1/rpc/get_workout_changes",
                         token, payload=body)
            feed = reply.data
            _require(reply.status == 200 and isinstance(feed, dict)
                     and feed.get("schema_version") == 1
                     and feed.get("cursor_reset") is False
                     and isinstance(feed.get("changes"), list)
                     and isinstance(feed.get("cursor_epoch"), str),
                     "restore_feed_invalid_" + str(index))
            _uuid(feed["cursor_epoch"], "restore_epoch_" + str(index))
            if epoch is not None:
                _require(epoch == feed["cursor_epoch"],
                         "restore_epoch_rotated_during_audit")
            epoch = feed["cursor_epoch"]
            changes = feed["changes"]
            for change in changes:
                _require(isinstance(change, dict)
                         and isinstance(change.get("workout_id"), str),
                         "restore_change_invalid_" + str(index))
                _require(change["workout_id"] != other,
                         "cross_owner_restore_leak_" + str(index))
                observed.add(change["workout_id"])
            next_cursor = feed.get("next_cursor")
            _require(type(next_cursor) is int and next_cursor >= cursor,
                     "restore_cursor_invalid_" + str(index))
            _require(type(feed.get("has_more")) is bool,
                     "restore_has_more_invalid_" + str(index))
            if feed["has_more"] is False:
                break
            _require(next_cursor > cursor and len(changes) > 0,
                     "restore_cursor_not_progressing_" + str(index))
            cursor = next_cursor
        else:
            raise AuditFailure("restore_feed_over_100_pages")
        _require(own in observed, "fixture_missing_from_restore_" + str(index))
        passed.append("owner_" + str(index) + "_restore_isolation")

    for index, (owner, workout) in enumerate(
            ((accounts[0], workout_a), (accounts[1], workout_b))):
        anonymous = records(None, owner, workout)
        _require(anonymous.status in (401, 403)
                 or (anonymous.status == 200 and anonymous.data == []),
                 "anonymous_record_access_" + str(index))
        passed.append("anonymous_cannot_read_owner_" + str(index))

    return passed


def main() -> int:
    if os.environ.get("NS_P2_08_DISPOSABLE_ACK") != "nonproduction-disposable-only":
        print("FAIL: disposable_nonproduction_ack_required", file=sys.stderr)
        return 2
    fields = ("NS_P2_08_URL", "NS_P2_08_PUBLISHABLE_KEY",
              "NS_P2_08_JWT_A", "NS_P2_08_JWT_B",
              "NS_P2_08_WORKOUT_A", "NS_P2_08_WORKOUT_B")
    if any(not os.environ.get(field) for field in fields):
        print("FAIL: required_environment_missing", file=sys.stderr)
        return 2
    try:
        checks = run_audit(
            _requester(os.environ["NS_P2_08_URL"],
                       os.environ["NS_P2_08_PUBLISHABLE_KEY"]),
            os.environ["NS_P2_08_JWT_A"],
            os.environ["NS_P2_08_JWT_B"],
            os.environ["NS_P2_08_WORKOUT_A"],
            os.environ["NS_P2_08_WORKOUT_B"])
    except AuditFailure as error:
        print("FAIL: " + str(error), file=sys.stderr)
        return 1
    # Safe to attach to release evidence: no account or workout identifiers.
    print("PASS: " + str(len(checks)) + " signed-JWT read-isolation checks")
    for name in checks:
        print("PASS: " + name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
