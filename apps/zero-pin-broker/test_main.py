# Unit tests for PoW replay protection, rate limits, code resolution, and TURN credentials.
import os
import time
import unittest
from fastapi.testclient import TestClient
from main import (
    app,
    POW_LEADING_HEX_ZEROS,
    _mem_records,
    _mem_used_pow,
    _mem_rate_limits,
    compute_argon2id_pow,
)

def solve_argon2id_pow_for_test(ip: str, ts: int) -> str:
    prefix = "0" * POW_LEADING_HEX_ZEROS
    nonce = 0
    while True:
        digest = compute_argon2id_pow(ip, str(nonce), ts)
        if digest.hex().startswith(prefix):
            return str(nonce)
        nonce += 1

class ZeroIdentityBrokerTests(unittest.TestCase):
    def setUp(self):
        _mem_records.clear()
        _mem_used_pow.clear()
        _mem_rate_limits.clear()
        self.client = TestClient(app)

    def test_healthcheck_and_security_headers(self):
        for route in ("/health", "/healthz"):
            resp = self.client.get(route)
            self.assertEqual(resp.status_code, 200)
            self.assertEqual(resp.json()["status"], "ok")
            self.assertEqual(resp.json()["pow"], "argon2id")
            self.assertEqual(resp.headers.get("X-Content-Type-Options"), "nosniff")
            self.assertEqual(resp.headers.get("X-Frame-Options"), "DENY")
            self.assertEqual(resp.headers.get("Referrer-Policy"), "no-referrer")

    def test_4word_phrase_and_deeplink_roundtrip(self):
        ts = int(time.time())
        nonce = solve_argon2id_pow_for_test("127.0.0.1", ts)
        invite = "zero:/contact#/?v=2-7&smp=smp%3A%2F%2Fsmp1.simpl.global"
        res = self.client.post(
            "/api/v1/identity/phrase",
            json={"invite_url": invite, "nonce": nonce, "timestamp": ts},
        )
        self.assertEqual(res.status_code, 200)
        body = res.json()
        phrase = body["phrase"]
        slug = body["slug"]
        self.assertRegex(phrase, r"^[A-Z][a-z]+-[A-Z][a-z]+-[A-Z][a-z]+-[A-Z][a-z]+$")
        self.assertTrue(body["deep_link"].startswith("https://simpl.global/add/"))

        res_phrase = self.client.get(f"/api/v1/identity/resolve/{phrase.lower().replace('-', ' ')}")
        self.assertEqual(res_phrase.status_code, 200)
        self.assertEqual(res_phrase.json()["invite_url"], invite)
        self.assertEqual(res_phrase.json()["kind"], "phrase")

        res_slug = self.client.get(f"/api/v1/identity/resolve/{slug}")
        self.assertEqual(res_slug.status_code, 200)
        self.assertEqual(res_slug.json()["invite_url"], invite)
        self.assertEqual(res_slug.json()["kind"], "deep_link")

    def test_ephemeral_6digit_code_roundtrip(self):
        ts = int(time.time())
        nonce = solve_argon2id_pow_for_test("127.0.0.1", ts)
        invite = "zero:/contact#/?v=2-7&smp=smp%3A%2F%2Fsmp1.simpl.global"
        res = self.client.post(
            "/api/v1/identity/ephemeral",
            json={"invite_url": invite, "nonce": nonce, "timestamp": ts},
        )
        self.assertEqual(res.status_code, 200)
        code = res.json()["code"]
        self.assertEqual(res.json()["expires_in"], 300)
        self.assertRegex(code, r"^\d{3}-\d{3}$")

        r1 = self.client.get(f"/api/v1/identity/resolve/{code}")
        self.assertEqual(r1.status_code, 200)
        self.assertEqual(r1.json()["kind"], "ephemeral")

        r2 = self.client.get(f"/api/v1/identity/resolve/{code.replace('-', '')}")
        self.assertEqual(r2.status_code, 200)
        self.assertEqual(r2.json()["invite_url"], invite)

    def test_replay_argon2id_pow_rejected(self):
        ts = int(time.time())
        nonce = solve_argon2id_pow_for_test("127.0.0.1", ts)
        payload = {
            "invite_url": "zero:/contact#/?v=2-7",
            "nonce": nonce,
            "timestamp": ts,
        }
        first = self.client.post("/api/v1/identity/phrase", json=payload)
        self.assertEqual(first.status_code, 200)

        replay = self.client.post("/api/v1/identity/phrase", json=payload)
        self.assertEqual(replay.status_code, 429)

    def test_expired_timestamp_rejected(self):
        stale_ts = int(time.time()) - 600
        nonce = solve_argon2id_pow_for_test("127.0.0.1", stale_ts)
        res = self.client.post(
            "/api/v1/identity/ephemeral",
            json={"invite_url": "zero:/contact#/?v=2-7", "nonce": nonce, "timestamp": stale_ts},
        )
        self.assertEqual(res.status_code, 429)

    def test_invalid_scheme_rejected(self):
        ts = int(time.time())
        nonce = solve_argon2id_pow_for_test("127.0.0.1", ts)
        res = self.client.post(
            "/api/v1/identity/phrase",
            json={"invite_url": "javascript:alert(1)", "nonce": nonce, "timestamp": ts},
        )
        self.assertEqual(res.status_code, 400)

    def test_rate_limiting_on_resolve_and_ip_hashing(self):
        for _ in range(30):
            r = self.client.get("/api/v1/identity/resolve/999-999")
            self.assertEqual(r.status_code, 404)
        limited = self.client.get("/api/v1/identity/resolve/999-999")
        self.assertEqual(limited.status_code, 429)
        for key in _mem_rate_limits:
            self.assertNotIn("127.0.0.1", key)
            self.assertNotIn("testclient", key)

    def test_loopback_proxy_real_ip_isolation(self):
        from starlette.requests import Request
        from main import _rate_limit_bucket_id

        req_loopback_a = Request({"type": "http", "client": ("127.0.0.1", 50000), "headers": [(b"x-real-ip", b"198.51.100.10")]})
        req_loopback_b = Request({"type": "http", "client": ("127.0.0.1", 50001), "headers": [(b"x-real-ip", b"198.51.100.20")]})
        req_direct_spoof = Request({"type": "http", "client": ("203.0.113.5", 50002), "headers": [(b"x-real-ip", b"198.51.100.10")]})
        self.assertNotEqual(_rate_limit_bucket_id(req_loopback_a), _rate_limit_bucket_id(req_loopback_b))
        self.assertNotEqual(_rate_limit_bucket_id(req_direct_spoof), _rate_limit_bucket_id(req_loopback_a))

    def test_placeholder_turn_secret_rejected(self):
        os.environ["TURN_AUTH_SECRET"] = "REPLACE_WITH_SHARED_TURN_AUTH_SECRET"
        try:
            res = self.client.get("/api/v1/turn/credentials")
            self.assertEqual(res.status_code, 503)
        finally:
            os.environ.pop("TURN_AUTH_SECRET", None)

    def test_ephemeral_turn_credentials(self):
        os.environ["TURN_AUTH_SECRET"] = "test-hmac-secret-key"
        try:
            res = self.client.get("/api/v1/turn/credentials")
            self.assertEqual(res.status_code, 200)
            data = res.json()
            self.assertEqual(data["ttl"], 3600)
            self.assertEqual(data["video_max_bitrate_bps"], 1_000_000)
            self.assertIn("stun:zeroturn.simpl.global:3478", data["uris"])
            self.assertIn("turn:zeromedia.simpl.global:3478?transport=udp", data["uris"])
            self.assertRegex(data["username"], r"^\d+:[0-9a-f]{16}$")
            self.assertTrue(len(data["credential"]) > 10)
        finally:
            os.environ.pop("TURN_AUTH_SECRET", None)

if __name__ == "__main__":
    unittest.main()
