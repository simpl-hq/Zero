# Regression tests for Argon2id invite-bound PoW, EFF wordlist entropy, rate limiting, and TURN tokens.
import os
import time
import unittest
from fastapi.testclient import TestClient
from main import (
    app,
    POW_LEADING_HEX_ZEROS,
    POW_LEADING_ZERO_BITS,
    WORDLIST,
    _EPHEMERAL_RL_KEY,
    _has_leading_zero_bits,
    _mem_records,
    _mem_used_pow,
    _mem_rate_limits,
    _rate_limit_hmac_key,
    compute_argon2id_pow,
)

def solve_argon2id_pow_for_test(invite_url: str, ts: int) -> str:
    nonce = 0
    while True:
        digest = compute_argon2id_pow(invite_url, str(nonce), ts)
        if _has_leading_zero_bits(digest, POW_LEADING_ZERO_BITS):
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

    def test_eff_7776_wordlist_integrity(self):
        self.assertEqual(len(WORDLIST), 7776)
        self.assertEqual(len({w.lower() for w in WORDLIST}), 7776)
        self.assertTrue(all(w.isalpha() and w.isascii() for w in WORDLIST))

    def test_4word_phrase_and_deeplink_roundtrip(self):
        ts = int(time.time())
        invite = "zero:/contact#/?v=2-7&smp=smp%3A%2F%2Fzerorelay.simpl.global:5223"
        nonce = solve_argon2id_pow_for_test(invite, ts)
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
        invite = "zero:/contact#/?v=2-7&smp=smp%3A%2F%2Fzerorelay.simpl.global:5223"
        nonce = solve_argon2id_pow_for_test(invite, ts)
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
        invite = "zero:/contact#/?v=2-7"
        nonce = solve_argon2id_pow_for_test(invite, ts)
        payload = {
            "invite_url": invite,
            "nonce": nonce,
            "timestamp": ts,
        }
        first = self.client.post("/api/v1/identity/phrase", json=payload)
        self.assertEqual(first.status_code, 200)

        replay = self.client.post("/api/v1/identity/phrase", json=payload)
        self.assertEqual(replay.status_code, 429)

    def test_pow_bound_to_invite_url_prevents_tampering(self):
        ts = int(time.time())
        invite_a = "zero:/contact#/?v=2-7&a=1"
        invite_b = "zero:/contact#/?v=2-7&b=2"
        nonce = solve_argon2id_pow_for_test(invite_a, ts)
        res = self.client.post(
            "/api/v1/identity/phrase",
            json={"invite_url": invite_b, "nonce": nonce, "timestamp": ts},
        )
        self.assertEqual(res.status_code, 429)

    def test_expired_timestamp_rejected(self):
        stale_ts = int(time.time()) - 600
        invite = "zero:/contact#/?v=2-7"
        nonce = solve_argon2id_pow_for_test(invite, stale_ts)
        res = self.client.post(
            "/api/v1/identity/ephemeral",
            json={"invite_url": invite, "nonce": nonce, "timestamp": stale_ts},
        )
        self.assertEqual(res.status_code, 429)

    def test_invalid_scheme_rejected(self):
        ts = int(time.time())
        invite = "javascript:alert(1)"
        nonce = solve_argon2id_pow_for_test(invite, ts)
        res = self.client.post(
            "/api/v1/identity/phrase",
            json={"invite_url": invite, "nonce": nonce, "timestamp": ts},
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
            self.assertEqual(_rate_limit_hmac_key(), _EPHEMERAL_RL_KEY)
        finally:
            os.environ.pop("TURN_AUTH_SECRET", None)

    def test_shared_worker_rate_limit_hmac_key(self):
        os.environ["TURN_AUTH_SECRET"] = "shared-cluster-turn-secret"
        try:
            k1 = _rate_limit_hmac_key()
            k2 = _rate_limit_hmac_key()
            self.assertEqual(len(k1), 32)
            self.assertEqual(k1, k2)
            self.assertNotEqual(k1, _EPHEMERAL_RL_KEY)
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

    def test_support_relay_success_and_rate_limit(self):
        payload = {
            "message": "Hello Simpl team, I have a question about Zero security.",
            "sender_pin": "brave-falcon-ocean-stone",
            "client_version": "1.0.0",
            "platform": "Desktop",
        }
        res = self.client.post("/api/v1/support/relay", json=payload)
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertEqual(data["status"], "received")
        self.assertEqual(data["relayed_to"], "support@simpl.global")
        self.assertTrue(len(data["ticket_id"]) >= 6)

        # Trigger rate limiting (10 per minute)
        for _ in range(12):
            res = self.client.post("/api/v1/support/relay", json=payload)
        self.assertEqual(res.status_code, 429)

if __name__ == "__main__":
    unittest.main()
