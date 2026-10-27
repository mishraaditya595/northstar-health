"""Offline failure-path regression tests for the P2-08 signed-JWT audit.

These tests never use live JWTs or the network. Real-account hosted validation
is a separate and still mandatory release gate.
"""
import io
import urllib.request
import urllib.response
import unittest
from unittest import mock

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
EPOCH = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
ROTATED = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"


class FakeHostedApi:
    """Each flag introduces exactly one fault at its corresponding check."""

    def __init__(
        self, *, missing_a=False, cross_user_leak=False,
        uuid_only_leak=False, point_lookup_leak=False,
        restore_leak=False, anonymous_access=False,
        epoch_rotation=False, stalled_cursor=False,
        over_100_pages=False, missing_restore_fixture=False,
        missing_has_more=False, nonboolean_has_more=False,
        invalid_epoch=False, anonymous_identity=False,
        http_error=False,
    ):
        self.missing_a = missing_a
        self.cross_user_leak = cross_user_leak
        self.uuid_only_leak = uuid_only_leak
        self.point_lookup_leak = point_lookup_leak
        self.restore_leak = restore_leak
        self.anonymous_access = anonymous_access
        self.epoch_rotation = epoch_rotation
        self.stalled_cursor = stalled_cursor
        self.over_100_pages = over_100_pages
        self.missing_restore_fixture = missing_restore_fixture
        self.missing_has_more = missing_has_more
        self.nonboolean_has_more = nonboolean_has_more
        self.invalid_epoch = invalid_epoch
        self.anonymous_identity = anonymous_identity
        self.http_error = http_error
        self.calls = []

    def __call__(self, method, path, token=None, query=None, payload=None):
        self.calls.append((method, path, token, query, payload))
        owner = {"token-a": A, "token-b": B}.get(token)
        if path == "/auth/v1/user":
            if self.http_error:
                return Reply(403, None)
            return Reply(200, {
                "id": owner, "is_anonymous": self.anonymous_identity,
            })
        if path == "/rest/v1/workout_records":
            target_workout = (query or {}).get("workout_id", "").removeprefix("eq.")
            target_owner = (query or {}).get("user_id", "")
            actual_owner = {WA: A, WB: B}.get(target_workout)
            if owner is None and not self.anonymous_access:
                return Reply(401, None)
            if not actual_owner:
                return Reply(200, [])
            if target_owner and target_owner != "eq." + actual_owner:
                return Reply(200, [])
            if target_workout == WA and self.missing_a and owner == A:
                return Reply(200, [])
            allowed = owner == actual_owner
            if owner is None and self.anonymous_access:
                allowed = True
            if owner != actual_owner and target_owner and self.cross_user_leak:
                allowed = True
            if owner != actual_owner and not target_owner and self.uuid_only_leak:
                allowed = True
            if allowed:
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
            allowed = owner == actual_owner or self.point_lookup_leak
            return Reply(200, {
                "schema_version": 1,
                "change": {"workout_id": workout} if allowed else None,
            })
        if path == "/rest/v1/rpc/get_workout_changes":
            workout = {A: WA, B: WB}[owner]
            other = {A: WB, B: WA}[owner]
            after = payload["p_after_seq"]
            feed = {
                "schema_version": 1,
                "cursor_epoch": EPOCH,
                "cursor_reset": False,
                "next_cursor": 1,
                "has_more": False,
                "changes": [{"workout_id": workout}],
            }
            if owner == A:
                if self.restore_leak:
                    feed["changes"].append({"workout_id": other})
                if self.missing_restore_fixture:
                    feed["changes"] = []
                    feed["next_cursor"] = 0
                if self.invalid_epoch:
                    feed["cursor_epoch"] = "not-a-uuid"
                if self.epoch_rotation:
                    feed["cursor_epoch"] = ROTATED if after else EPOCH
                    feed["has_more"] = after == 0
                    feed["next_cursor"] = after + 1
                if self.stalled_cursor:
                    feed["has_more"] = True
                    feed["next_cursor"] = after
                if self.over_100_pages:
                    feed["has_more"] = True
                    feed["next_cursor"] = after + 1
                if self.nonboolean_has_more:
                    feed["has_more"] = "false"
                if self.missing_has_more:
                    del feed["has_more"]
            return Reply(200, feed)
        raise AssertionError("Unexpected request " + path)


class _FakeHttpsHandler(urllib.request.HTTPSHandler):
    """Send HTTP status/Location through urllib's actual opener machinery."""

    def __init__(self, status, location=None):
        super().__init__()
        self.status = status
        self.location = location
        self.requests = []

    def https_open(self, request):
        self.requests.append(request)
        headers = {"Location": self.location} if self.location else {}
        # HTTPErrorProcessor dispatches redirects/4xx as a real opener would.
        return urllib.response.addinfourl(
            io.BytesIO(b'{"error":"confidential"}'), headers,
            request.full_url, code=self.status,
        )


class HostedReadAuditTests(unittest.TestCase):
    def audit(self, **faults):
        return run_audit(
            FakeHostedApi(**faults), "token-a", "token-b", WA, WB,
        )

    def test_verified_distinct_sessions_and_owner_isolation_pass(self):
        checks = self.audit()
        self.assertEqual(len(checks), 14)
        self.assertIn("owner_0_restore_isolation", checks)

    def test_empty_or_wrong_fixture_must_not_fake_success(self):
        with self.assertRaisesRegex(AuditFailure, "own_completed_fixture_missing_0"):
            self.audit(missing_a=True)

    def test_cross_user_explicit_owner_select_leak(self):
        with self.assertRaisesRegex(AuditFailure, "cross_owner_select_leak_0"):
            self.audit(cross_user_leak=True)

    def test_uuid_only_leak_without_owner_filter(self):
        # This must reach UUID-only SELECT: an explicit owner filter can hide
        # a permissive RLS policy.
        fake = FakeHostedApi(uuid_only_leak=True)
        with self.assertRaisesRegex(AuditFailure, "cross_owner_uuid_leak_0"):
            run_audit(fake, "token-a", "token-b", WA, WB)
        self.assertTrue(any(
            path == "/rest/v1/workout_records" and
            query.get("workout_id") == "eq." + WB and "user_id" not in query
            for _, path, _, query, _ in fake.calls if query is not None
        ))

    def test_point_lookup_leak(self):
        with self.assertRaisesRegex(AuditFailure, "cross_owner_point_lookup_leak_0"):
            self.audit(point_lookup_leak=True)

    def test_restore_feed_cross_owner_leak(self):
        with self.assertRaisesRegex(AuditFailure, "cross_owner_restore_leak_0"):
            self.audit(restore_leak=True)

    def test_unauthenticated_read_leak(self):
        with self.assertRaisesRegex(AuditFailure, "anonymous_record_access_0"):
            self.audit(anonymous_access=True)

    def test_epoch_rotation_during_pagination(self):
        with self.assertRaisesRegex(
            AuditFailure, "restore_epoch_rotated_during_audit",
        ):
            self.audit(epoch_rotation=True)

    def test_stalled_restore_cursor(self):
        with self.assertRaisesRegex(
            AuditFailure, "restore_cursor_not_progressing_0",
        ):
            self.audit(stalled_cursor=True)

    def test_unbounded_restore_feed_aborts_at_100_pages(self):
        fake = FakeHostedApi(over_100_pages=True)
        with self.assertRaisesRegex(
            AuditFailure, "restore_feed_over_100_pages",
        ):
            run_audit(fake, "token-a", "token-b", WA, WB)
        self.assertEqual(sum(
            path == "/rest/v1/rpc/get_workout_changes"
            for _, path, _, _, _ in fake.calls
        ), 100)

    def test_missing_fixture_from_restore_feed(self):
        with self.assertRaisesRegex(
            AuditFailure, "fixture_missing_from_restore_0",
        ):
            self.audit(missing_restore_fixture=True)

    def test_missing_has_more_fails_closed(self):
        with self.assertRaisesRegex(
            AuditFailure, "restore_has_more_invalid_0",
        ):
            self.audit(missing_has_more=True)

    def test_nonboolean_has_more_fails_closed(self):
        with self.assertRaisesRegex(
            AuditFailure, "restore_has_more_invalid_0",
        ):
            self.audit(nonboolean_has_more=True)

    def test_invalid_epoch_error_identifies_owner(self):
        with self.assertRaisesRegex(
            AuditFailure, "restore_epoch_0_invalid",
        ):
            self.audit(invalid_epoch=True)

    def test_anonymous_identity_even_when_auth_endpoint_returns_200(self):
        with self.assertRaisesRegex(AuditFailure, "a_anonymous_not_permitted"):
            self.audit(anonymous_identity=True)

    def test_http_error_status_from_fake_fails_audit(self):
        with self.assertRaisesRegex(AuditFailure, "a_jwt_not_verified"):
            self.audit(http_error=True)

    def test_same_token_cannot_impersonate_another_owner(self):
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

    def _request_with_fake_https(self, handler, method="GET", payload=None):
        original_build_opener = urllib.request.build_opener

        def build_opener(*handlers):
            # Disable environment proxies; no outbound connection is possible.
            return original_build_opener(
                *handlers, urllib.request.ProxyHandler({}), handler,
            )

        with mock.patch(
            "scripts.p2_08_hosted_rls.urllib.request.build_opener",
            side_effect=build_opener,
        ):
            caller = _requester("https://test.supabase.co", "test-public-key")
            return caller(method, "/auth/v1/user", "test-private-token",
                          payload=payload)

    def test_redirects_do_not_resend_credentials_to_other_host_or_http(self):
        # All redirect variants, including POST-preserving 307/308, are
        # rejected BEFORE any request is made to Location.
        for status in (301, 302, 303, 307, 308):
            for destination in (
                "https://redirected.example/collect",
                "http://redirected.example/collect",
            ):
                with self.subTest(status=status, destination=destination):
                    handler = _FakeHttpsHandler(status, destination)
                    method = "POST" if status in (307, 308) else "GET"
                    payload = {"check": True} if method == "POST" else None
                    with self.assertRaisesRegex(
                        AuditFailure, "^unexpected_redirect$",
                    ):
                        self._request_with_fake_https(
                            handler, method=method, payload=payload,
                        )
                    self.assertEqual(len(handler.requests), 1)
                    request = handler.requests[0]
                    self.assertEqual(
                        request.full_url, "https://test.supabase.co/auth/v1/user",
                    )
                    self.assertEqual(
                        request.get_header("Authorization"),
                        "Bearer test-private-token",
                    )
                    self.assertEqual(
                        request.get_header("Apikey"), "test-public-key",
                    )

    def test_redirect_without_location_also_fails_closed(self):
        handler = _FakeHttpsHandler(302)
        with self.assertRaisesRegex(AuditFailure, "^unexpected_redirect$"):
            self._request_with_fake_https(handler)
        self.assertEqual(len(handler.requests), 1)

    def test_real_urllib_http_error_path_discards_sensitive_body(self):
        handler = _FakeHttpsHandler(403)
        result = self._request_with_fake_https(handler)
        self.assertEqual(result, Reply(403, None))
        self.assertEqual(len(handler.requests), 1)


if __name__ == "__main__":
    unittest.main()
