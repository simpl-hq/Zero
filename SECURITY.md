<div align="center">

<h1>Zero — Security Policy &amp; Audit Scope</h1>

<p>Transparent audit status, cryptographic scope, and responsible vulnerability disclosure.</p>

<p>
  <a href="https://simpl.global"><img src="media-logos/btn-simpl-global.svg" alt="Website — simpl.global" height="38" /></a>
  <a href="README.md"><img src="media-logos/btn-readme.svg" alt="README" height="38" /></a>
  <a href="WHITEPAPER.md"><img src="media-logos/btn-whitepaper.svg" alt="Whitepaper" height="38" /></a>
  <a href="https://simpl.global/donate"><img src="media-logos/btn-donate.svg" alt="Support Zero" height="38" /></a>
</p>

</div>

---

## Independent Audit & Component Scope

Zero builds upon the open-source [SimpleX Chat](https://github.com/simplex-chat/simplex-chat) unidirectional messaging core (`AGPL-3.0`, Copyright © 2021–2026 SimpleX Chat Ltd; Zero extensions Copyright © 2026 Simpl LLC) and adds Simpl's pairing broker, ephemeral TURN authority, volatile-key cluster infrastructure, and native client onboarding. We distinguish clearly between **independently audited upstream primitives** and **Simpl `v1.0.0` extensions**:

| Component | Repository Path | Audit Status | Notes |
| :--- | :--- | :--- | :--- |
| **`Upstream SMP / XFTP / PQDR Core`** | [`src/`](src) · [`vendor/zeroq/`](vendor/zeroq) | **Inherited Upstream Audits** *(Trail of Bits 2022, Cure53 2024)* | Upstream protocol primitives (`Curve448` + `sntrup761` Double Ratchet, `16 KB` padding, `SQLCipher`) audited on the upstream SimpleX Chat codebase; Simpl's `v1.0.0` fork itself has not yet undergone a separate re-audit. |
| **`Contact-Code Pairing Broker`** | [`apps/zero-pin-broker/main.py`](apps/zero-pin-broker/main.py) | **Not Yet Audited** *(Open-Source Review)* | Stateless Python/FastAPI service implementing the 7,776-word EFF phrase generator, invite-bound 10-bit `Argon2id` PoW (`m=8 MiB, t=1, p=1`), daily-rotating HMAC rate-limit buckets, and ephemeral HMAC-SHA1 TURN tokens. Optional for users and fully self-hostable or disableable. |
| **`Client PoW & Broker Bridges`** | [`ZeroInfo.swift`](apps/ios/Shared/Views/Onboarding/ZeroInfo.swift) · [`ZeroIdentityBridge.kt`](apps/multiplatform/common/src/commonMain/kotlin/app/zero/core/network/ZeroIdentityBridge.kt) | **Not Yet Audited** *(Open-Source Review)* | Native Swift/Kotlin 10-bit `Argon2id` PoW solvers, TLS CA SPKI/DER certificate pinning on default Simpl broker hosts, fail-closed SOCKS5/Tor proxy enforcement, strict `zero:/` resolved URI validation, and custom/disabled broker isolation (`ZeroDirectoryUrl = off` with zero silent fallback to `simpl.global`). |
| **`Volatile Cluster & Relay Infra`** | [`deploy/`](deploy) · [`scripts/relay/`](scripts/relay) | **Not Yet Audited** *(Open-Source Review)* | WireGuard mesh (`10.10.0.0/24`), RAM-key `cryptsetup` (`aes-xts-plain64`) blob storage + swap, `tmpfs` state directories, and log-discarding Caddy/Coturn edge configs. |
| **`Desktop Setup & Packaging`** | [`ZeroSetup.cs`](apps/multiplatform/desktop/src/jvmMain/resources/distribute/windows/ZeroSetup.cs) · [`build-windows-setup.ps1`](scripts/desktop/build-windows-setup.ps1) | **Open-Source Review** | Isolated `%LOCALAPPDATA%\ZeroSetup` staging, SHA-256 verification of the embedded `Zero.msi` payload prior to execution, target path validation, and CI Authenticode signing hooks. |

---

## Cryptographic & Threat-Model Boundaries

- **Network & Relay Adversaries:** Unidirectional `SMP` queues, TLS 1.3 SPKI certificate pinning, `16 KB` packet padding, and optional 2-hop onion routing protect payloads and social graphs even against curious or compromised relay operators.
- **Rendezvous Lookup Privacy & Broker Trust:** Both Android/Desktop ([`ZeroIdentityBridge.kt`](apps/multiplatform/common/src/commonMain/kotlin/app/zero/core/network/ZeroIdentityBridge.kt)) and iOS ([`ZeroInfo.swift`](apps/ios/Shared/Views/Onboarding/ZeroInfo.swift)) enforce pinned TLS chains on Simpl brokers, fail closed when SOCKS5/Tor is enabled, reject non-`zero:/` resolved URIs, and never fall back to `simpl.global` when a custom or `off` broker setting is configured. Because convenience phrase/code lookups are untrusted rendezvous rather than PKI-bound identities, verify each contact's **Security Code** (out-of-band fingerprint) inside chat info to defeat first-contact MitM.
- **Physical Device Compromise:** Zero cannot defend plaintext on an unlocked, unencrypted host OS. Enable OS full-disk encryption, Face ID / App Lock, and a local `SQLCipher` database passphrase in **Settings**.

---

## Reporting a Vulnerability

If you discover a security, privacy, or cryptographic vulnerability in the protocol, client applications, contact broker, or cluster configurations:

1. **Do not** open a public GitHub issue, pull request, or forum thread before remediation.
2. Send reproduction steps, affected component paths, and impact details privately to **`support@simpl.global`**.
3. We acknowledge reports within **48 hours** and coordinate patched releases with full researcher credit (or anonymous credit, if preferred).

---

<div align="center">

<p>
  <a href="https://simpl.global"><img src="media-logos/btn-simpl-global.svg" alt="Website — simpl.global" height="38" /></a>
  <a href="README.md"><img src="media-logos/btn-readme.svg" alt="README" height="38" /></a>
  <a href="https://simpl.global/donate"><img src="media-logos/btn-donate.svg" alt="Support Zero" height="38" /></a>
</p>

<sub>**&copy; 2026 Simpl.** Zero is free software licensed under the [GNU Affero General Public License v3.0](LICENSE). · [simpl.global](https://simpl.global) · [Donate](https://simpl.global/donate) · [README.md](README.md) · [WHITEPAPER.md](WHITEPAPER.md) · [PRIVACY.md](PRIVACY.md) · `support@simpl.global`</sub>

</div>
