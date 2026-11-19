<div align="center">

<h1>Contributing to Zero</h1>

<p>Architecture, verification suites, and contribution guidelines for the Zero post-quantum messenger.</p>

<p>
  <a href="https://simpl.global"><img src="media-logos/btn-simpl-global.svg" alt="Website — simpl.global" height="38" /></a>
  <a href="README.md"><img src="media-logos/btn-readme.svg" alt="README" height="38" /></a>
  <a href="WHITEPAPER.md"><img src="media-logos/btn-whitepaper.svg" alt="Whitepaper" height="38" /></a>
  <a href="https://simpl.global/donate"><img src="media-logos/btn-donate.svg" alt="Support Zero" height="38" /></a>
</p>

</div>

---

## Repository Architecture

| Path | Language / Stack | Role |
| :--- | :--- | :--- |
| [`vendor/zeroq`](vendor/zeroq) | Haskell (`GHC 9.6.3`) + C | Core `SMP` queues, `XFTP` encrypted file transfer, `Curve448` + `sntrup761` Double Ratchet, TLS pinning, relay daemons |
| [`src/`](src) | Haskell | `zero-runtime` chat state, SQLite/Postgres `SQLCipher` stores, remote control, Bot API, C FFI exports |
| [`apps/ios`](apps/ios) | Swift / SwiftUI | Native iOS client, `Zero NSE` notification extension, `Zero SE` share extension, Face ID local lock |
| [`apps/multiplatform`](apps/multiplatform) | Kotlin Multiplatform / Compose + C11 | Android (`google` / `foss`), Desktop (`macOS`, `Windows`, `Linux`), and JNI C11 bridge (`zero-api.c`) |
| [`apps/zero-pin-broker`](apps/zero-pin-broker) | Python / FastAPI / Redis | Identifier-free 4-word phrase & 6-digit code broker, Argon2id PoW verifier, HMAC-SHA1 TURN tokens |
| [`packages/`](packages) | Node.js N-API, Python, TypeScript | Developer SDK bindings and WebRTC client libraries |
| [`deploy/`](deploy) & [`scripts/relay/`](scripts/relay) | Docker / Caddy / Coturn / Bash | Multi-region relay, database, CDN media, and self-hosting definitions |

---

## Coding & Review Guidelines

1. **No Identifiers or Telemetry:** Never introduce phone numbers, usernames, advertising IDs, analytics trackers, or third-party SDKs that phone home. Android `foss` builds (`apps/multiplatform/android/build.gradle.kts`) must remain completely free of proprietary Google Play dependencies.
2. **Preserve Cryptographic & FFI Invariants:**
   - Any changes to C exports in [`src/Zero/Chat/Mobile.hs`](src/Zero/Chat/Mobile.hs) must stay symmetric across desktop and Android JNI bridges (`apps/multiplatform/common/src/commonMain/cpp/{desktop,android}/zero-api.c`) and Kotlin `external fun` signatures.
   - Keep `commoncrypto` (`SecRandomCopyBytes`) compliance intact on Apple builds (`vendor/zeroq/zeroq.cabal`).
3. **Database Migrations:** Never rewrite shipped migration modules (`src/Zero/Chat/Store/{SQLite,Postgres}/Migrations/`); add incremental migrations instead.
4. **Cross-Platform UI Parity:** User-facing onboarding, privacy settings, and help guides should remain clear, accessible, and consistent across iOS, Android, and Desktop.

---

## Local Verification & Tests

Run the components available on your target platform before opening a pull request:

```bash
# 1. Contact-Code Broker & Argon2id PoW API tests (Python 3.11+)
python -B -m unittest discover -s apps/zero-pin-broker -p "test_main.py" -v

# 2. Core Messaging & Chat integration suites (requires GHC 9.6.3 / Cabal)
cabal test all

# 3. Android & Desktop clients (requires JDK 17+ / Android SDK)
cd apps/multiplatform && ./gradlew testDesktopTest check

# 4. iOS client (requires macOS / Xcode)
xcodebuild -project apps/ios/Zero.xcodeproj -scheme Zero test
```

---

## Submitting Pull Requests

1. Fork [github.com/simpl-hq/zero](https://github.com/simpl-hq/zero) and create a focused branch from `main`.
2. Keep pull requests scoped to a single fix or feature and reference any related issue template (`[Bug]` or `[Feature]`).
3. Include tests or reproduction steps for bug fixes, protocol parser changes, or UI regressions.

## Security Vulnerability Disclosure

If you discover a security or privacy vulnerability in the protocol, client apps, or relay software, **do not open a public GitHub issue**. Report reproduction details privately to `support@simpl.global`.

## Support Zero

Zero collects **zero user data. Ever.** No investors, no ads, no trackers. Development and stateless relay infrastructure are funded directly by the community at **[simpl.global/donate](https://simpl.global/donate)**:

<div align="center">

<a href="https://simpl.global"><img src="media-logos/btn-simpl-global.svg" alt="Website — simpl.global" height="38" /></a>
<a href="https://simpl.global/donate"><img src="media-logos/btn-donate.svg" alt="Support Zero" height="38" /></a>

</div>

<br />

| Channel | Address / Link |
| :--- | :--- |
| **`Buy Me a Coffee`** | [buymeacoffee.com/supportsimpl](https://buymeacoffee.com/supportsimpl) |
| **`Monero (XMR)`** | `47hCGy2csT1fJXMbsVtstXDqudH2M6tyeVQed9ob4vjgawLMnRqA5sNESBrGsfoiEQNCFWbohXsTG9JDfVWCh5KgVhTcrrL` |
| **`Bitcoin (BTC)`** | `bc1qwdz5r5vagtqq8mmn0wch2y6q5adk4ms84xj3es` |
| **`ETH / USDC (ERC-20, Base, Arbitrum, Polygon)`** | `0x96A103A67cB65c33673275FEFA29C77807E52605` |

## License

Contributions to source code are licensed under the [GNU Affero General Public License v3.0](LICENSE) (upstream messaging and transport stack Copyright © 2021–2026 SimpleX Chat Ltd; Zero modifications and extensions Copyright © 2026 Simpl LLC). Visual brand assets remain covered by [assets/ASSETS_LICENSE.md](assets/ASSETS_LICENSE.md).

---

<div align="center">

<sub>**© 2026 Simpl.** Zero is free software licensed under the [GNU Affero General Public License v3.0](LICENSE). · [simpl.global](https://simpl.global) · [Donate](https://simpl.global/donate) · [README.md](README.md) · [WHITEPAPER.md](WHITEPAPER.md) · [CHANGELOG.md](CHANGELOG.md) · `support@simpl.global`</sub>

</div>
