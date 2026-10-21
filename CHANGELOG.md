# Changelog

All notable changes to **Zero** across core messaging, client applications (iOS, Android, macOS, Windows, Linux, CLI), SDK bindings, and relay infrastructure are documented in this file.

See [README.md](README.md) for downloads, [WHITEPAPER.md](WHITEPAPER.md) for the protocol specification, and [simpl.global](https://simpl.global) for releases.

---

## [1.0.0] — 2026-11-16

### Added
- Initial open-source **`v1.0.0`** launch release of **Zero** across desktop (`macOS`, `Windows`, `Linux`), CLI, direct Android APK, multi-language runtime SDKs, and mobile clients submitted for App Store and Google Play review under Simpl (`simpl.global`).
- Interactive 4-step Guided Setup Tutorial (`ZeroGuidedTutorialView` across iOS `HowItWorks.swift` and Compose Multiplatform `HowItWorks.kt`) integrated into onboarding, home cards, help views, and Desktop empty workspace navigation.
- End-to-end test suite (`apps/zero-pin-broker/test_main.py`) verifying 4-word phrase provisioning, 6-digit ephemeral in-person pairing codes, replay rejection, sliding-window rate limits, HMAC-SHA1 TURN credentials, and `/health` + `/healthz` probes.
- Updated `WHITEPAPER.md`, `README.md`, Flatpak `app.zero.core.zero.metainfo.xml`, and Linux AppStream `app.zero.chat.appdata.xml` release metadata.

### Changed
- Unified monorepo version tags to `1.0.0` (`1.0.0.0` in `zero-runtime.cabal` and renamed internal queue/transport engine `vendor/zeroq/zeroq.cabal`) and synchronized UI/FFI version strings across Haskell, Swift, Kotlin, and localized resources.
- Standardized RFC 9106 Argon2id contact-code proof-of-work (`m=8 MiB, t=1, p=1`) consistently across iOS (`ZeroInfo.swift`), Android/Desktop (`Argon2idPow.kt`, `ZeroIdentityBridge.kt`), and the FastAPI broker (`apps/zero-pin-broker/main.py`).
- Hardened `apps/zero-pin-broker` (volatile per-process HMAC-SHA256 rate-limit buckets over loopback `X-Real-IP`, bounded fallback state, fail-closed `TURN_AUTH_SECRET` placeholder validation, non-root `broker` container user, and Compose `cap_drop: ALL`) alongside strict HTTPS-only default broker resolution in iOS and Kotlin clients.

### Fixed
- Hardened cluster scripts and database configs (`deploy/bootstrap-node.sh` WireGuard `wg0` UFW rules + Docker boot ordering, `node3-db` `scram-sha-256` & fail-closed Redis checks, `node4-media/blob_cleanup.sh` `pipefail`-safe eviction, and `scripts/relay/{smp-server.ini, xftp-server.ini}` schema parity).
- Normalized `simpl.global/add/...` deep-link validation in `apps/zero-pin-broker/main.py` (`400` on invalid URLs), fixed non-hex commit rendering in `VersionView.swift` / `VersionInfoView.kt`, fixed portable architecture detection (`uname -m`) in server install/update scripts, and cleaned up localization and onboarding strings ahead of the `v1.0.0` release.

---

## [0.9.6] — 2026-11-04

### Changed
- Split Android packaging into `google` and dependency-free `foss` flavors (`apps/multiplatform/android/build.gradle.kts`) for F-Droid and direct GitHub APK verification.
- Refined iOS Face ID / local biometric lock prompts and app-switcher blur transitions across `Zero NSE` and foreground resume.
- Adjusted `zero-pin-broker` Redis client connect/read timeouts (`0.15s`) so transient Redis restarts or single-node dev checks fall back cleanly without blocking workers.

### Fixed
- Guarded broker `/api/v1/identity/resolve/{target}` and `/api/v1/turn/credentials` routes with rate limiting and strict response headers (`Cache-Control: no-store`, `X-Content-Type-Options: nosniff`).
- Fixed Compose Desktop window focus and notification activation edge cases on macOS and Windows.

---

## [0.9.5] — 2026-10-20

### Added
- Multi-region 4-node cluster deployment configurations under `deploy/` (`node1-na`, `node2-eu`, `node3-db` WireGuard-isolated Postgres + Redis, `node4-media` overflow CDN + Coturn + Uptime Kuma) with `bootstrap-node.sh` host hardening.
- Ephemeral encrypted XFTP blob expiration pruning (`deploy/node4-media/blob_cleanup.sh`).

### Changed
- Configured `--denied-peer-ip` RFC 1918 / loopback filters in `turnserver.conf` across relay nodes to block WebRTC TURN reflection attacks.
- Standardized Caddy reverse-proxy TLS configs across `zeroapi.simpl.global`, `zerorelay.simpl.global`, `zeroturn.simpl.global`, `zerocdn.simpl.global`, and `zeromedia.simpl.global`.

### Fixed
- Audited JNI UTF-8 string marshaling and native buffer capacity bounds across `apps/multiplatform/common/src/commonMain/cpp/desktop/zero-api.c` and `android/zero-api.c`.
- Verified Windows GHC 9.6 non-moving GC workaround flags in `packages/zero-runtime-nodejs/cpp/zero.cc` and `desktop/zero-api.c`.

---

## [0.9.4] — 2026-10-04

### Changed
- Tuned background delivery polling intervals and wake-lock handoffs between iOS `Zero NSE` (`NotificationService.swift`) and Android `MessagesFetcherWorker.kt` to lower idle battery drain.
- Added Argon2id challenge timestamp window (`±300s`) and spent-challenge replay protection in the contact broker.

### Fixed
- Fixed race condition when flushing queued delivery notifications immediately after unlocking the SQLCipher database with a local passphrase.
- Resolved Linux AppImage `.desktop` and shared OpenSSL `libcrypto` staging cleanup trap on aborted packaging runs.

---

## [0.9.3] — 2026-09-18

### Added
- Identifier-free FastAPI contact-code broker (`apps/zero-pin-broker`) supporting 30-day 4-word phrases, 5-minute in-person 6-digit pairing codes, and ephemeral coturn TURN credentials.
- Reproducible build scripts (`scripts/zero-runtime-reproduce-builds.sh`) pinned to GHC `9.6.3`.

### Changed
- Froze remote desktop-to-mobile version negotiation bounds (`minRemoteCtrlVersion` / `minRemoteHostVersion` `[1, 0, 0, 0]`) and SMP relay handshakes ahead of release candidate testing.

---

## [0.9.0] — 2026-09-01

### Added
- Multi-language runtime bindings under `packages/`: Node.js N-API native addon (`zero-runtime-nodejs`), Python ctypes runtime wrapper (`zero-runtime-python`), and TypeScript client/bot types (`zero-runtime-client`, `@zero-runtime/types`).
- Directory service bot (`apps/zero-directory-service`) supporting search, group listing approval, and text/audio verification checks.
- Finalized Postgres and SQLite schema parity migrations (`M20260714`–`M20260720` member security codes, signed history, server roles).

### Fixed
- Fixed native library cache resolution and platform artifact naming across Windows, macOS (`arm64` / `x86_64`), and Linux (`sqlite` and `postgres` backends).
- Addressed duplicate delivery receipt emission on reconnect after server-side queue cursor advancement.

---

## [0.8.5] — 2026-08-16

### Added
- Group and broadcast channel role permissions (`observer`, `member`, `moderator`, `admin`, `owner`) with member security-code verification and signed history checkpoints.
- Multi-relay channel delivery and automatic roster catch-up sync for newly admitted members.
- Channel HTML preview card generator and extended user profile descriptions.

### Changed
- Reorganized Settings navigation hierarchy across SwiftUI and Compose Multiplatform clients for faster access to security, network, and storage controls.

---

## [0.8.2] — 2026-07-28

### Fixed
- Added `commoncrypto` Cabal build flag in `vendor/zeroq` routing `libbbs` randomness through `SecRandomCopyBytes` on Apple platforms so iOS App Store builds avoid private-API `getentropy` rejections (`ITMS-90338`).
- Improved relay request retry backoff tracking (`M20260429`, `M20260507`) and link phishing / query-tracker sanitization before generating link previews.

---

## [0.8.0] — 2026-07-10

### Added
- Chat list organization filters (unread, favorites, custom folders/lists) and batch message selection (forward up to 20 messages, bulk moderation).
- Member contact request throttling and private abuse reports routed exclusively to group administrators (`Zero.Chat.Operators`).

### Changed
- Reduced group broadcast latency and sped up large-group local deletion queries via SQLite index tuning.

---

## [0.7.0] — 2026-06-22

### Added
- Multiple local chat profiles with strict per-profile or per-connection relay transport isolation (`Zero.Chat.Store.Profiles`).
- Hidden profiles gated by separate passcodes and full-wipe self-destruct passcode support.
- Pre-admission group review ("knocking") allowing prospective members and moderators to converse prior to acceptance.
- `@mention` parsing and notification highlighting in groups.

---

## [0.6.0] — 2026-06-03

### Added
- End-to-end encrypted WebRTC audio and video calling (`Zero.Chat.Call`, `packages/zero-runtime-webrtc`) with DTLS-SRTP fingerprint exchange over SMP and forced TURN relay toggle.
- Encrypted local media/file storage (images, voice clips, documents) and QR-based cross-device profile migration (`MigrateToDevice`).
- Picture-in-picture active call overlay on iOS and Android.

---

## [0.5.0] — 2026-05-15

### Added
- Augmented Post-Quantum Double Ratchet (`PQDR`) integrating Streamlined NTRU Prime 761 (`sntrup761`) KEM into every forward-secret ratchet step alongside Curve448 Diffie-Hellman.
- 2-hop onion private message routing (`Zero.Chat` proxy relay selection) decoupling sender IP addresses from recipient home relays.
- SOCKS5 proxy routing options (Tor / isolated circuit credentials per profile) and TLS server SPKI certificate pinning.

---

## [0.4.0] — 2026-04-26

### Added
- Extended File Transfer Protocol (`XFTP`) chunked symmetric-encrypted uploads and downloads (`1 GiB` base limit, configurable up to `5 GiB` quota tiers) plus web fallback bundle (`vendor/zeroq/xftp-web`).
- Desktop-to-mobile remote device control (`Zero.Chat.Remote`, `RevHTTP.hs`) over encrypted local pairing.
- Kotlin Multiplatform + Compose UI desktop (macOS, Windows, Linux) and Android clients sharing the C11 JNI FFI bridge (`zero-api.c`).
- Live message streaming, emoji reactions, message edits with version history, disappearing-message timers, and quote replies.

---

## [0.3.0] — 2026-04-08

### Added
- Private end-to-end encrypted group messaging with pairwise member state isolation, group invite links, and welcome messages.
- Initial iOS SwiftUI client (`apps/ios`), `Zero NSE` Notification Service Extension, and `Zero SE` Share Extension targets.
- One-time contact invitation URIs, reusable contact addresses, and double-tick delivery receipts.

---

## [0.2.0] — 2026-03-26

### Added
- Core `Zero Messaging Protocol (SMP)` client and stateless relay daemon (`vendor/zeroq`) with unidirectional Ed448-authenticated queues and fixed `16,384`-byte agent packet padding.
- SQLCipher 256-bit AES + HMAC-SHA512 encrypted local persistence (`direct-sqlcipher`, `sqlcipher-simple`) and versioned schema migration runner across SQLite and PostgreSQL backends.

---

## [0.1.0] — 2026-03-16

### Added
- Initial repository architecture: Haskell chat core (`zero-runtime.cabal`), messaging/transport runtime (`vendor/zeroq`), C FFI boundary (`Zero.Chat.Mobile`), and interactive terminal client (`Zero.Chat.Terminal`).
- Automated Hspec integration suites (`tests/`, `vendor/zeroq/tests/`) for handshake, ratchet, serialization, and markdown link validation.
