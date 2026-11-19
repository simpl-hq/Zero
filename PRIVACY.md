<div align="center">

<h1>Zero — Privacy Policy</h1>

<p>Minimalist, identifier-free messaging verified by open mathematics rather than corporate policy.</p>

<p>
  <a href="https://simpl.global"><img src="media-logos/btn-simpl-global.svg" alt="Website — simpl.global" height="38" /></a>
  <a href="README.md"><img src="media-logos/btn-readme.svg" alt="README" height="38" /></a>
  <a href="WHITEPAPER.md"><img src="media-logos/btn-whitepaper.svg" alt="Whitepaper" height="38" /></a>
  <a href="https://simpl.global/donate"><img src="media-logos/btn-donate.svg" alt="Support Zero" height="38" /></a>
</p>

</div>

---

| Guarantee | Implementation | Retention / Visibility |
| :--- | :--- | :--- |
| **`Identifiers & Accounts`** | No phone numbers, emails, usernames, or social graphs | None collected |
| **`End-to-End Encryption`** | Post-quantum `Curve448` + `sntrup761` Double Ratchet (`16 KB` padded blocks) | Keys remain client-side |
| **`Local Persistence`** | Encrypted `SQLCipher` (`AES-256` + `HMAC-SHA512`) | Stored only on user device |
| **`Relay & File Buffers`** | Stateless zero-log `SMP` & volatile `XFTP` (`AES-256-XTS` RAM-key vault) | Deleted on delivery or expiry |
| **`Contact Pairing Broker`** | `Argon2id` PoW · daily rotating HMAC rate-limit buckets | 30-day phrase / 5-min code TTL |

---

## Core Commitments

- **No identifiers or accounts:** Zero never asks for phone numbers, email addresses, usernames, or advertising IDs, and builds no centralized social graph.
- **Post-quantum end-to-end encryption:** Every message uses an augmented Double Ratchet pairing `Curve448` with `sntrup761` KEM inside fixed `16 KB` padded blocks, stored locally in `SQLCipher`.
- **Stateless zero-log relays:** Messages and `XFTP` file chunks buffer encrypted only until delivery or automatic expiry (`24h` volatile-key purge on media nodes), with web/relay access logs discarded.
- **Open-source verifiability:** Every client, broker, and relay component is public under [`AGPL-3.0`](LICENSE).

---

<div align="center">

<p>
  <a href="https://simpl.global"><img src="media-logos/btn-simpl-global.svg" alt="Website — simpl.global" height="38" /></a>
  <a href="README.md"><img src="media-logos/btn-readme.svg" alt="README" height="38" /></a>
  <a href="https://simpl.global/donate"><img src="media-logos/btn-donate.svg" alt="Support Zero" height="38" /></a>
</p>

<sub>**© 2026 Simpl.** Zero is free software licensed under the [GNU Affero General Public License v3.0](LICENSE). · [simpl.global](https://simpl.global) · [Donate](https://simpl.global/donate) · [README.md](README.md) · [WHITEPAPER.md](WHITEPAPER.md) · `support@simpl.global`</sub>

</div>
