# Changelog (`zeroq`)

Release history for the `zeroq` messaging broker, client agent, `SMP` queue protocol, push notification server, and `XFTP` encrypted file transfer core.

See the root [CHANGELOG.md](../../CHANGELOG.md), [README.md](../../README.md), and [WHITEPAPER.md](../../WHITEPAPER.md).

---

## [1.0.0] — 2026-11-16

- Initial **`v1.0.0`** open-source release of the `zeroq` (`1.0.0.0`) messaging broker, `SMP` queue protocol, push notification server, and `XFTP` encrypted file transfer libraries under Simpl (`simpl.global`).
- Finalized `zeroq` (`Zero Queue`) internal Cabal package and script naming, updated `install.sh` / `zero-servers-update` architecture detection (`uname -m`), and normalized Linux script line endings.
- Updated HTML fallback and web endpoints (`apps/common/Web/static/`, `apps/xftp-server/static/`, `xftp-web/package.json`) to reference `WHITEPAPER.md`, `PRIVACY.md`, `simpl.global`, and `github.com/simpl-hq/zero`.

## [0.9.6] — 2026-11-04

- Hardened client TLS socket timeouts and retry jitter during relay failover across `node1-na` and `node2-eu` clusters.
- Verified `CLITests` server banner formatting (`SMP server`, `SMP notifications server`, `Zero XFTP server`).

## [0.9.5] — 2026-10-20

- Updated Prometheus metrics exporters (`Zero.Messaging.Server.Prometheus`, `Zero.FileTransfer.Server.Prometheus`) and XFTP expiry cleanup hooks.

## [0.9.3] — 2026-09-18

- Froze `SMP` and `XFTP` binary wire protocol negotiation ranges (`VersionRangeTests`) ahead of `v1.0.0` release candidate validation.

## [0.8.2] — 2026-07-28

- Added `-f commoncrypto` Cabal flag to route `libbbs` randomness through `SecRandomCopyBytes` on Apple targets, eliminating App Store private symbol `getentropy` warnings (`ITMS-90338`).

## [0.5.0] — 2026-05-15

- Integrated `sntrup761` post-quantum KEM alongside `X448` inside the per-step `DoubleRatchet` key schedule (`cbits/sntrup761.h`).
- Implemented 2-hop onion forwarding proxy support (`sendingProxySMPVersion`) and SOCKS5 isolate-by-auth parsing (`SOCKSSettings`).

## [0.4.0] — 2026-04-26

- Added `Zero.FileTransfer` (`XFTP`) encrypted fixed-chunk upload/download server, client agent, and `xftp-web` browser decryption bundle.

## [0.2.0] — 2026-03-26

- Implemented unidirectional `SMP` resource queues, fixed `16,384`-byte packet padding, batch framing (`BatchingTests`), and SQLCipher encrypted agent storage.

## [0.1.0] — 2026-03-16

- Initial extraction of `Zero.Messaging` and `Zero.Messaging.Agent` transport, cryptographic primitives (`Ed25519`, `Ed448`, `X448`, `blst`/`libbbs`), and TLS SPKI pinning.
