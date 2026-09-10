# FastAPI pin broker for 4-word phrases, 6-digit codes, Argon2id PoW checks, and TURN credentials.
import base64
import hashlib
import hmac
import os
import re
import secrets
import threading
import time
from typing import Dict, List, Optional, Tuple
from argon2.low_level import Type as Argon2Type, hash_secret_raw
from fastapi import FastAPI, HTTPException, Request, Response
from pydantic import BaseModel, Field

try:
    import redis
except ImportError:
    redis = None

REDIS_HOST = os.environ.get("REDIS_HOST", "localhost")
REDIS_PORT = int(os.environ.get("REDIS_PORT", "6379"))
REDIS_PASSWORD = os.environ.get("REDIS_PASSWORD") or None

app = FastAPI(title="Zero Identity & Ephemeral Broker", docs_url=None, redoc_url=None)
db = (
    redis.Redis(
        host=REDIS_HOST,
        port=REDIS_PORT,
        password=REDIS_PASSWORD,
        decode_responses=True,
        socket_connect_timeout=0.15,
        socket_timeout=0.15,
    )
    if redis is not None
    else None
)
_redis_backoff_until: float = 0.0

def _get_redis():
    global _redis_backoff_until
    if db is None or time.time() < _redis_backoff_until:
        return None
    return db

def _trip_redis_circuit():
    global _redis_backoff_until
    _redis_backoff_until = time.time() + 30.0

ARGON2_SALT = b"zero-argon2id-pow"
ARGON2_TIME_COST = 1
ARGON2_MEMORY_COST = 8192
ARGON2_PARALLELISM = 1
ARGON2_HASH_LEN = 32
POW_LEADING_HEX_ZEROS = 1
POW_WINDOW_SECONDS = 300

PHRASE_TTL_SECONDS = 2592000
EPHEMERAL_TTL_SECONDS = 300
MAX_INVITE_URL_LEN = 4096
PROVISION_RATE_LIMIT_PER_MIN = 30
RESOLVE_RATE_LIMIT_PER_MIN = 30
DEEP_LINK_BASE = "https://simpl.global/add/"
MAX_MEM_RATE_BUCKETS = 4096
MAX_MEM_RECORDS = 16384

_EPHEMERAL_RL_KEY = secrets.token_bytes(32)

PHRASE_PATTERN = re.compile(r"^[a-z]+-[a-z]+-[a-z]+-[a-z]+$")
EPHEMERAL_PATTERN = re.compile(r"^\d{3}-\d{3}$")
SLUG_PATTERN = re.compile(r"^[A-Za-z0-9_\-]{8,32}$")
NONCE_PATTERN = re.compile(r"^[A-Za-z0-9_\-]{1,64}$")
SAFE_IP_PATTERN = re.compile(r"^[A-Fa-f0-9\.\:]{3,45}$")

WORDLIST: Tuple[str, ...] = (
    "Acorn", "Amber", "Anchor", "Anvil", "Apex", "Apple", "Arbor", "Arctic",
    "Arrow", "Ash", "Aspen", "Atlas", "Atom", "Aurora", "Autumn", "Azure",
    "Badger", "Bamboo", "Beacon", "Birch", "Bison", "Blaze", "Bloom", "Boulder",
    "Breeze", "Bridge", "Bronze", "Brook", "Canyon", "Carbon", "Cedar", "Chalk",
    "Cinder", "Cipher", "Citrus", "Cliff", "Cloud", "Clover", "Cobalt", "Comet",
    "Copper", "Coral", "Cosmos", "Coyote", "Crater", "Creek", "Crest", "Crimson",
    "Crown", "Crystal", "Cypress", "Dagger", "Dawn", "Delta", "Desert", "Diamond",
    "Dolphin", "Drift", "Dune", "Dusk", "Eagle", "Echo", "Eclipse", "Elder",
    "Ember", "Emerald", "Falcon", "Feather", "Fern", "Fjord", "Flame", "Flint",
    "Forest", "Forge", "Fossil", "Fox", "Frost", "Galaxy", "Garden", "Garnet",
    "Geyser", "Glacier", "Glade", "Glimmer", "Granite", "Gravel", "Grove", "Harbor",
    "Harvest", "Hawk", "Hazel", "Hearth", "Heather", "Helix", "Heron", "Hollow",
    "Horizon", "Hunter", "Iceberg", "Indigo", "Iron", "Island", "Ivory", "Jade",
    "Jaguar", "Jasper", "Juniper", "Kestrel", "Kettle", "Keystone", "Kodiak", "Lagoon",
    "Lantern", "Lark", "Laurel", "Lava", "Leaf", "Lichen", "Light", "Linen",
    "Lotus", "Lunar", "Lynx", "Magnet", "Maple", "Marble", "Marsh", "Meadow",
    "Mercury", "Meteor", "Mica", "Mirror", "Mist", "Monarch", "Moon", "Moss",
    "Mountain", "Nebula", "Nectar", "Needle", "Nimbus", "Noble", "North", "Nova",
    "Nutmeg", "Oak", "Oasis", "Obsidian", "Ocean", "Ochre", "Olive", "Onyx",
    "Opal", "Orbit", "Orchid", "Oriole", "Osprey", "Otter", "Owl", "Ozone",
    "Panther", "Pebble", "Pelican", "Pepper", "Petal", "Phantom", "Phoenix", "Pine",
    "Pioneer", "Planet", "Platinum", "Plume", "Polar", "Poplar", "Prism", "Puma",
    "Quartz", "Quill", "Quiver", "Rain", "Raven", "Redwood", "Reef", "Ridge",
    "Ripple", "River", "Robin", "Rocket", "Rose", "Ruby", "Sable", "Saffron",
    "Sage", "Sapphire", "Saturn", "Scarlet", "Sequoia", "Shadow", "Shale", "Shell",
    "Shield", "Sierra", "Signal", "Silver", "Slate", "Snow", "Solar", "Solstice",
    "Spark", "Sparrow", "Specter", "Sphere", "Spruce", "Star", "Steel", "Stone",
    "Storm", "Stream", "Summit", "Sun", "Swallow", "Swift", "Tempest", "Thistle",
    "Thorn", "Thunder", "Tiger", "Timber", "Topaz", "Torch", "Torrent", "Trail",
    "Trident", "Tundra", "Umber", "Valiant", "Valley", "Vapor", "Vector", "Velvet",
    "Vertex", "Vesper", "Vortex", "Voyager", "Walnut", "Wave", "Whisper", "Willow",
    "Wind", "Winter", "Wolf", "Wren", "Zenith", "Zephyr", "Zinc", "Zodiac",
)

_mem_lock = threading.Lock()
_mem_records: Dict[str, Tuple[str, float, int]] = {}
_mem_used_pow: Dict[str, float] = {}
_mem_rate_limits: Dict[str, List[float]] = {}

class IdentityPayload(BaseModel):
    invite_url: str = Field(..., min_length=8, max_length=MAX_INVITE_URL_LEN)
    nonce: str = Field(..., min_length=1, max_length=64)
    timestamp: int

@app.middleware("http")
async def apply_security_headers(request: Request, call_next):
    response: Response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Content-Security-Policy"] = "default-src 'none'"
    return response

def _sanitize_ip(raw_ip: str) -> str:
    candidate = raw_ip.strip()
    if SAFE_IP_PATTERN.match(candidate):
        return candidate
    return "127.0.0.1"

def _rate_limit_bucket_id(request: Request) -> str:
    peer_host = request.client.host if request.client else "127.0.0.1"
    subject = _sanitize_ip(peer_host)
    if peer_host in ("127.0.0.1", "::1"):
        forwarded_ip = request.headers.get("x-real-ip", "").strip()
        if forwarded_ip and SAFE_IP_PATTERN.match(forwarded_ip):
            subject = forwarded_ip
    return hmac.new(_EPHEMERAL_RL_KEY, subject.encode("utf-8"), hashlib.sha256).hexdigest()[:24]

def _check_rate_limit(bucket_key: str, max_requests: int, window_seconds: int = 60) -> bool:
    r = _get_redis()
    if r is not None:
        try:
            key = f"ratelimit:{bucket_key}"
            count = r.incr(key)
            if count == 1:
                r.expire(key, window_seconds)
            return int(count) <= max_requests
        except Exception:
            _trip_redis_circuit()
    now = time.time()
    cutoff = now - window_seconds
    with _mem_lock:
        if len(_mem_rate_limits) >= MAX_MEM_RATE_BUCKETS:
            for existing_key in list(_mem_rate_limits.keys()):
                fresh = [ts for ts in _mem_rate_limits[existing_key] if ts > cutoff]
                if fresh:
                    _mem_rate_limits[existing_key] = fresh
                else:
                    del _mem_rate_limits[existing_key]
            if len(_mem_rate_limits) >= MAX_MEM_RATE_BUCKETS:
                return False
        timestamps = [ts for ts in _mem_rate_limits.get(bucket_key, []) if ts > cutoff]
        if len(timestamps) >= max_requests:
            _mem_rate_limits[bucket_key] = timestamps
            return False
        timestamps.append(now)
        _mem_rate_limits[bucket_key] = timestamps
        return True

def _validate_invite_url(invite_url: str) -> str:
    cleaned = invite_url.strip()
    if any(ord(ch) < 32 or ord(ch) == 127 for ch in cleaned):
        raise HTTPException(status_code=400, detail="Control characters prohibited in invite URL.")
    if not (cleaned.startswith("zero:/") or cleaned.startswith("https://")):
        raise HTTPException(status_code=400, detail="Invalid Zero invite URL scheme.")
    return cleaned

def _mark_pow_used(pow_hash: str) -> bool:
    ttl = POW_WINDOW_SECONDS * 2
    r = _get_redis()
    if r is not None:
        try:
            return bool(r.set(f"pow:used:{pow_hash}", "1", nx=True, ex=ttl))
        except Exception:
            _trip_redis_circuit()
    now = time.time()
    with _mem_lock:
        expired = [k for k, exp in _mem_used_pow.items() if exp <= now]
        for k in expired:
            del _mem_used_pow[k]
        if len(_mem_used_pow) >= MAX_MEM_RECORDS:
            return False
        if pow_hash in _mem_used_pow:
            return False
        _mem_used_pow[pow_hash] = now + ttl
        return True

def _store_if_absent(store_key: str, invite_url: str, ttl: int) -> bool:
    r = _get_redis()
    if r is not None:
        try:
            return bool(r.set(store_key, invite_url, nx=True, ex=ttl))
        except Exception:
            _trip_redis_circuit()
    now = time.time()
    with _mem_lock:
        if len(_mem_records) >= MAX_MEM_RECORDS:
            expired = [k for k, entry in _mem_records.items() if entry[1] <= now]
            for k in expired:
                del _mem_records[k]
            if len(_mem_records) >= MAX_MEM_RECORDS:
                return False
        entry = _mem_records.get(store_key)
        if entry and entry[1] > now:
            return False
        _mem_records[store_key] = (invite_url, now + ttl, ttl)
        return True

def _delete_key(store_key: str) -> None:
    r = _get_redis()
    if r is not None:
        try:
            r.delete(store_key)
            return
        except Exception:
            _trip_redis_circuit()
    with _mem_lock:
        _mem_records.pop(store_key, None)

def _lookup_key(store_key: str, refresh_ttl: bool = False) -> Optional[str]:
    r = _get_redis()
    if r is not None:
        try:
            val = r.get(store_key)
            if val is not None and refresh_ttl:
                r.expire(store_key, PHRASE_TTL_SECONDS)
            return val
        except Exception:
            _trip_redis_circuit()
    now = time.time()
    with _mem_lock:
        entry = _mem_records.get(store_key)
        if not entry:
            return None
        val, exp, ttl = entry
        if exp <= now:
            del _mem_records[store_key]
            return None
        if refresh_ttl:
            _mem_records[store_key] = (val, now + ttl, ttl)
        return val

def compute_argon2id_pow(client_ip: str, nonce: str, timestamp: int) -> bytes:
    payload = f"{client_ip}:{timestamp}:{nonce}".encode("utf-8")
    return hash_secret_raw(
        secret=payload,
        salt=ARGON2_SALT,
        time_cost=ARGON2_TIME_COST,
        memory_cost=ARGON2_MEMORY_COST,
        parallelism=ARGON2_PARALLELISM,
        hash_len=ARGON2_HASH_LEN,
        type=Argon2Type.ID,
    )

def verify_argon2id_pow(client_ip: str, nonce: str, timestamp: int) -> bool:
    if not NONCE_PATTERN.match(nonce):
        return False
    if abs(time.time() - timestamp) > POW_WINDOW_SECONDS:
        return False
    digest = compute_argon2id_pow(client_ip, nonce, timestamp)
    hex_digest = digest.hex()
    if not hex_digest.startswith("0" * POW_LEADING_HEX_ZEROS):
        return False
    replay_token = hashlib.sha256(f"{client_ip}:{timestamp}:{nonce}".encode("utf-8")).hexdigest()
    return _mark_pow_used(replay_token)

def _generate_4word_phrase() -> str:
    words = [WORDLIST[secrets.randbelow(len(WORDLIST))] for _ in range(4)]
    return "-".join(words)

def _generate_ephemeral_code() -> str:
    part1 = 100 + secrets.randbelow(900)
    part2 = 100 + secrets.randbelow(900)
    return f"{part1}-{part2}"

@app.get("/health")
@app.get("/healthz")
def healthz():
    return {"status": "ok", "pow": "argon2id"}

@app.post("/api/v1/identity/phrase")
def provision_phrase(payload: IdentityPayload, request: Request, client_ip: str = "127.0.0.1"):
    bucket_id = _rate_limit_bucket_id(request)
    if not _check_rate_limit(f"provision:{bucket_id}", PROVISION_RATE_LIMIT_PER_MIN, 60):
        raise HTTPException(status_code=429, detail="Too many identity provisioning requests. Try again shortly.")

    safe_ip = _sanitize_ip(client_ip if client_ip != "127.0.0.1" else "127.0.0.1")
    clean_invite = _validate_invite_url(payload.invite_url)

    if not verify_argon2id_pow(safe_ip, payload.nonce, payload.timestamp):
        raise HTTPException(status_code=429, detail="Argon2id anti-bot verification failed or replayed.")

    for _ in range(64):
        phrase = _generate_4word_phrase()
        slug = secrets.token_urlsafe(9)
        phrase_key = f"phrase:{phrase.lower()}"
        slug_key = f"slug:{slug}"
        if _store_if_absent(phrase_key, clean_invite, PHRASE_TTL_SECONDS):
            if _store_if_absent(slug_key, clean_invite, PHRASE_TTL_SECONDS):
                return {
                    "status": "authorized",
                    "phrase": phrase,
                    "slug": slug,
                    "deep_link": f"{DEEP_LINK_BASE}{slug}",
                }
            _delete_key(phrase_key)

    raise HTTPException(status_code=500, detail="Phrase namespace saturation error.")

@app.post("/api/v1/identity/ephemeral")
def provision_ephemeral_code(payload: IdentityPayload, request: Request, client_ip: str = "127.0.0.1"):
    bucket_id = _rate_limit_bucket_id(request)
    if not _check_rate_limit(f"provision:{bucket_id}", PROVISION_RATE_LIMIT_PER_MIN, 60):
        raise HTTPException(status_code=429, detail="Too many identity provisioning requests. Try again shortly.")

    safe_ip = _sanitize_ip(client_ip if client_ip != "127.0.0.1" else "127.0.0.1")
    clean_invite = _validate_invite_url(payload.invite_url)

    if not verify_argon2id_pow(safe_ip, payload.nonce, payload.timestamp):
        raise HTTPException(status_code=429, detail="Argon2id anti-bot verification failed or replayed.")

    for _ in range(100):
        code = _generate_ephemeral_code()
        digits = code.replace("-", "")
        if _store_if_absent(f"ephemeral:{digits}", clean_invite, EPHEMERAL_TTL_SECONDS):
            return {
                "status": "authorized",
                "code": code,
                "expires_in": EPHEMERAL_TTL_SECONDS,
            }

    raise HTTPException(status_code=500, detail="Ephemeral code space saturation error.")

@app.get("/api/v1/identity/resolve/{target}")
def resolve_identity(target: str, request: Request):
    bucket_id = _rate_limit_bucket_id(request)
    if not _check_rate_limit(f"resolve:{bucket_id}", RESOLVE_RATE_LIMIT_PER_MIN, 60):
        raise HTTPException(status_code=429, detail="Too many identity lookup requests. Try again shortly.")

    cleaned = target.strip()
    digits = re.sub(r"[\s\-]", "", cleaned)

    if len(digits) == 6 and digits.isdigit():
        invite_url = _lookup_key(f"ephemeral:{digits}", refresh_ttl=False)
        if not invite_url:
            raise HTTPException(status_code=404, detail="6-digit code expired or invalid.")
        return {"invite_url": invite_url, "kind": "ephemeral"}

    normalized_phrase = re.sub(r"[\s\-]+", "-", cleaned.lower())
    if PHRASE_PATTERN.match(normalized_phrase):
        invite_url = _lookup_key(f"phrase:{normalized_phrase}", refresh_ttl=True)
        if not invite_url:
            raise HTTPException(status_code=404, detail="4-word phrase not found or expired.")
        return {"invite_url": invite_url, "kind": "phrase"}

    if SLUG_PATTERN.match(cleaned):
        invite_url = _lookup_key(f"slug:{cleaned}", refresh_ttl=True)
        if not invite_url:
            raise HTTPException(status_code=404, detail="Invite link expired or invalid.")
        return {"invite_url": invite_url, "kind": "deep_link"}

    raise HTTPException(status_code=400, detail="Invalid 4-word phrase, deep link, or 6-digit code.")

TURN_CREDENTIAL_TTL_SECONDS = 3600
TURN_URIS = (
    "stun:zeroturn.simpl.global:3478",
    "turn:zeroturn.simpl.global:3478?transport=udp",
    "turns:zeroturn.simpl.global:5349?transport=tcp",
    "turn:zeromedia.simpl.global:3478?transport=udp",
)

@app.get("/api/v1/turn/credentials")
def get_ephemeral_turn_credentials(request: Request):
    bucket_id = _rate_limit_bucket_id(request)
    if not _check_rate_limit(f"turn:{bucket_id}", RESOLVE_RATE_LIMIT_PER_MIN, 60):
        raise HTTPException(status_code=429, detail="Too many TURN credential requests.")

    turn_secret = os.environ.get("TURN_AUTH_SECRET", "").strip()
    if not turn_secret or turn_secret.startswith("REPLACE_WITH_"):
        raise HTTPException(status_code=503, detail="TURN credential authority not configured.")

    expiry = int(time.time()) + TURN_CREDENTIAL_TTL_SECONDS
    username = f"{expiry}:{secrets.token_hex(8)}"
    digest = hmac.new(
        turn_secret.encode("utf-8"),
        username.encode("utf-8"),
        hashlib.sha1,
    ).digest()
    credential = base64.b64encode(digest).decode("ascii")

    return {
        "username": username,
        "credential": credential,
        "ttl": TURN_CREDENTIAL_TTL_SECONDS,
        "uris": list(TURN_URIS),
        "video_max_bitrate_bps": 1_000_000,
    }
