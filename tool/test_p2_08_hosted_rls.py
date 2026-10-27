"""Synthetic, offline negative/positive tests for P2-08 hosted read audit.

The live audit still requires real signed JWTs and a hosted test project; these
mocks only protect the audit's fail-closed expectations against regressions.
"""
import unittest

from scripts.p2_08_hosted_rls import (
    AuditFailure,
    Reply,
    _requester,
    run_audit,
)

A = "00000000-0000-4000-8000-000000000001"
B = "00000000-0000-4000-8000-000000000002"
WA = "10000000-0000-4000-8000-000000000001"
WB = "10000000-0000-4000-8000-000000000002"


class FakeHostedApi:
    def __init__(self, *, missing_a=False, leak=False, anonymous=False):
        self.missing_a = missing_a
        self.leak = leak
        self.anonymous = anonymous

    def __call__(self, method, path, token=None, query=None, payload=None):
        owner = {"token-a": A, "token-b": B}.get(token)
        if path == "/auth/v1/user":
            return Reply(200, {"id": owner, "is_anonymous": self.anonymous})
        if path == "/rest/v1/workout_records":
            if owner is None:
                return Reply(401, None)
            target_workout = (query or {}).get("workout_id", "").removeprefix("eq.")
            target_owner = (query or {}).get("user_id", "")
            actual_owner = {WA: A, WB: B}.get(target_workout)
            if target_owner and target_owner != "eq." + actual_owner:
                return Reply(200, [])
            if target_workout == WA and self.missing_a:
                return Reply(200, [])
            if actual_owner and (owner == actual_owner or self.leak):
                return Reply(200, [{
                    "user_id": actual_owner,
                    "workout_id": target_workout,
                    "status": "completed",
                    "deleted_at": None,
                    "server_revision": 1,
                    "server_change_seq": 1,
                }])
            return Reply(200, [])
        if path == "/rest/v1/rpc/get_workout_for_resolution":
            workout = payload["p_workout_id"]
            actual_owner = {WA: A, WB: B}[workout]
            change = ({"workout_id": workout} if owner == actual_owner
                      or self.leak else None)
            return Reply(200, {"schema_version": 1, "change": change})
        if path == "/rest/v1/rpc/get_workout_changes":
            workout = {A: WA, B: WB}[owner]
            return Reply(200, {
                "schema_version": 1,
                "cursor_epoch": "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
                "cursor_reset": False,
                "next_cursor": 1,
                "has_more": False,
                "changes": [{"workout_id": workout}],
            })
        raise AssertionError("Unexpected request " + path)


class HostedReadAuditTests(unittest.TestCase):
    def test_verified_distinct_sessions_and_owner_isolation_pass(self):
        checks = run_audit(FakeHostedApi(), "token-a", "token-b", WA, WB)
        self.assertEqual(len(checks), 14)
        self.assertIn("owner_0_restore_isolation", checks)

    def test_empty_or_wrong_fixture_must_not_fake_success(self):
        with self.assertRaisesRegex(AuditFailure, "own_completed_fixture_missing"):
            run_audit(FakeHostedApi(missing_a=True),
                      "token-a", "token-b", WA, WB)

    def test_cross_user_record_leak_is_rejected(self):
        with self.assertRaisesRegex(AuditFailure, "cross_owner_select_leak"):
            run_audit(FakeHostedApi(leak=True),
                      "token-a", "token-b", WA, WB)

    def test_anonymous_accounts_fail_even_if_jwt_request_returns_200(self):
        with self.assertRaisesRegex(AuditFailure, "anonymous_not_permitted"):
            run_audit(FakeHostedApi(anonymous=True),
                      "token-a", "token-b", WA, WB)

    def test_same_token_cannot_impersonate_second_device_or_owner(self):
        with self.assertRaisesRegex(AuditFailure, "two_distinct_sessions"):
            run_audit(FakeHostedApi(), "token-a", "token-a", WA, WB)

    def test_bad_workout_id_fails_before_contacting_backend(self):
        with self.assertRaisesRegex(AuditFailure, "fixture_a_invalid"):
            run_audit(FakeHostedApi(), "token-a", "token-b", "not-a-uuid", WB)

    def test_non_https_and_embedded_credentials_rejected(self):
        with self.assertRaisesRegex(AuditFailure, "hosted_https_url_required"):
            _requester("http://localhost:54321", "public")
        with self.assertRaisesRegex(AuditFailure, "hosted_https_url_required"):
            _requester("https://user:pass@test.supabase.co", "public")


if __name__ == "__main__":
    unittest.main()
