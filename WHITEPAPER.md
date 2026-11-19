<div align="center">

<h1>Zero — Technical Whitepaper</h1>

<p>Post-quantum forward secrecy and identifier-free unidirectional relay architecture.</p>

<p>
  <a href="https://simpl.global"><img src="media-logos/btn-simpl-global.svg" alt="Website — simpl.global" height="38" /></a>
  <a href="README.md"><img src="media-logos/btn-readme.svg" alt="README" height="38" /></a>
  <a href="https://github.com/simpl-hq/zero/releases"><img src="media-logos/btn-releases.svg" alt="Releases" height="38" /></a>
  <a href="https://simpl.global/donate"><img src="media-logos/btn-donate.svg" alt="Support Zero" height="38" /></a>
</p>

</div>

<br />

| Specification | Overview |
| :--- | :--- |
| **`Version & License`** | `v1.0.0` · [`AGPL-3.0`](LICENSE) |
| **`Post-Quantum E2EE`** | Augmented Double Ratchet (`Curve448` + `sntrup761` KEM) |
| **`Metadata & Traffic`** | Pairwise unidirectional queues · fixed `16 KB` padding · optional `2-hop` onion routing |
| **`Anti-Spam & Storage`** | `Argon2id` PoW (`m=8 MiB, t=1, p=1`) · `SQLCipher` AES-256 + `HMAC-SHA512` |

---

## Abstract

The evolution of secure messaging has largely solved the problem of message payload confidentiality but has consistently failed to adequately protect communication metadata. Dominant platforms inherently rely on global user identifiers—such as phone numbers, alphanumeric usernames, or static public keys—to route messages, thereby enabling the reconstruction of server-side social graphs. Zero introduces a radical paradigm shift: a post-quantum, mathematically secure network architecture that entirely eliminates global identifiers. By leveraging unidirectional ephemeral queues, 16 KB fixed-size packet padding, and an Augmented Post-Quantum Double Ratchet (PQDR), Zero provides a communication ecosystem resistant to both classical traffic analysis and future quantum decryption.

---

## 1. Introduction: The Metadata Vulnerability

Modern end-to-end encrypted (E2EE) protocols successfully secure data in transit and at rest. However, the reliance on central directories to discover and route messages leaves a permanent trail of metadata. This metadata reveals *who* is talking to *whom*, *when*, and *how often*.

Even advanced routing enhancements, such as "Sealed Sender" implementations, remain vulnerable to long-term traffic analysis and temporal correlation attacks. Zero builds upon the open-source SimpleX unidirectional queue protocol (`AGPL-3.0`, Copyright © 2021–2026 SimpleX Chat Ltd; Zero extensions Copyright © 2026 Simpl LLC) and extends it with an Argon2id identifier-free pairing broker, ephemeral TURN credential isolation, and volatile-key relay architecture—discarding centralized identity schemas entirely.

## 2. The Zero-Identifier Identity Model

In Zero, **no permanent user ID exists**.

Users do not register phone numbers, email addresses, usernames, or even static public-key hashes.

Connections are established exclusively via out-of-band invitations (e.g., sharing a secure link, 4-word phrase, 6-digit code, or scanning a QR code). This invitation contains the cryptographic parameters necessary to instantiate a dynamically negotiated, strictly unidirectional message queue. Because there are no identifiers, the network cannot be scraped, spammed by default, or mapped. To the network, a user is simply a localized endpoint interacting with transient resource URLs.

## 3. Network Architecture: Unidirectional Queues

The foundation of Zero is the Zero Messaging Protocol (SMP). Unlike conventional client-server architectures that maintain persistent, bidirectional connections bound to an identity, SMP operates exclusively on disposable, one-way message queues.

### 3.1 Decoupled Communication

A standard conversation between Alice and Bob requires at least two independent SMP queues, hosted on separate relays:

- **Alice** maintains a receive-queue on Relay A.
- **Bob** maintains a receive-queue on Relay B.

Relays act purely as stateless forwarders. An SMP router cannot mathematically or logically correlate a sender with a receiver. The server observes only a series of isolated message deliveries to opaque queue identifiers.

### 3.2 Private Onion Routing (2-Hop)

To protect IP addresses, Zero utilizes a multi-hop routing topology. When Alice sends a message to Bob, she connects to an arbitrary *forwarding relay*, which then transmits the packet to Bob's *receiving relay*. The forwarding relay knows Alice's IP but not the destination; the receiving relay knows the destination but not Alice's IP.

## 4. Cryptographic Design

Zero employs a multi-layered cryptographic envelope to ensure both absolute confidentiality and structural indistinguishability.

### 4.1 Augmented Post-Quantum Double Ratchet (PQDR)

To protect against "Harvest-Now, Decrypt-Later" attacks by adversaries with Cryptographically Relevant Quantum Computers (CRQCs), Zero injects a Post-Quantum Key Encapsulation Mechanism (KEM) into *every* ratchet step, rather than just the initial handshake.

The algorithm pairs classical Curve448 Diffie-Hellman keys with Streamlined NTRU Prime 761 (`sntrup761`). The key derivation sequence is mathematically defined as:

$$
\text{GENERATE\_PQKEM}() \rightarrow (ek, dk)
$$

$$
\text{PQKEM-ENC}(ek_{\text{peer}}) \rightarrow (ct, ss_{\text{pq}})
$$

$$
KDF(ss_{\text{classical}} \parallel ss_{\text{pq}}) \rightarrow \text{RootKey}
$$

An attacker must break both the classical discrete logarithm problem and the lattice-based Shortest Vector Problem (SVP) to decrypt the payload.

### 4.2 Traffic Obfuscation: 16 KB Padding

Statistical network analysis can deanonymize users by clustering message sizes. Zero neutralizes this by enforcing rigid Traffic Flow Confidentiality (TFC). Every standard agent message is padded to a fixed $16,384\text{ bytes}$ ($16\text{ KB}$) prior to transmission. To the network observer, a single emoji and a long paragraph look structurally identical.

### 4.3 Memory-Hard Proof of Work

To defend against infrastructure DoS attacks and automated contact-code scraping, Zero utilizes **Argon2id** (RFC 9106) with memory-hard parameters ($m=8\text{ MiB}, t=1, p=1$, 32-byte digest, 2 leading hex zeros / 8-bit difficulty $\approx 256$ hashes on average, $\pm 300\text{s}$ invite-bound replay window) across iOS, Android, and Desktop clients during 4-word phrase and 6-digit pairing-code issuance. Memory-hard verification adds computational cost against GPU or ASIC abuse while remaining responsive across mobile devices and client environments.

### 4.4 Independent Audit Scope

Zero's underlying `SMP`, `XFTP`, and `PQDR` cryptographic primitives build on the open-source SimpleX protocol stack (`AGPL-3.0`, independently audited upstream by Trail of Bits in 2022 and Cure53 in 2024). Simpl's `v1.0.0` extensions—including the ~1,360-line open-source [`apps/zero-pin-broker`](apps/zero-pin-broker) pairing service, native client `Argon2id` onboarding bridges, and 4-node volatile-storage cluster definitions—have **not yet undergone a separate independent third-party audit** and are published in full for community verification; see [`SECURITY.md`](SECURITY.md) for component-by-component details.

## 5. Media and Large Payload Routing

### 5.1 The XFTP Architecture

Payloads exceeding the $16\text{ KB}$ SMP limit are routed via the Extended File Transfer Protocol (XFTP). Files are encrypted using symmetric NaCl `secret_box`, broken into fixed-size chunks, and uploaded to XFTP relays. The decryption key and SHA-512 file digest are transmitted out-of-band via the secure SMP queue. The XFTP relay remains entirely oblivious to the file's true size, content, or filename.

### 5.2 WebRTC and TURN Relays

Real-time audio and video bypass store-and-forward queues, establishing peer-to-peer WebRTC connections. To prevent IP exposure during ICE negotiation, media traffic can be forcefully routed through ephemeral HMAC-SHA1 TURN relays. Call signaling and DTLS-SRTP certificate fingerprint exchanges are negotiated securely over the SMP layer, eliminating Man-in-the-Middle (MiTM) vulnerabilities.

## 6. Client-Side Sovereignty

Zero is inherently decentralized and self-sovereign. Relays are stateless; they store no user profiles, relationships, or long-term data. All persistent state—including messages, cryptographic ratchets, and contact rosters—is stored locally on the user's device.

Local databases are secured using **SQLCipher**, providing transparent 256-bit AES encryption. Each database page is cryptographically authenticated using HMAC-SHA512 signatures to prevent forensic tampering.

## 7. Conclusion

Zero represents a convergence of decentralized network theory and post-quantum cryptography. By systematically replacing centralized identity schemas with unidirectional, relationship-specific queues, the network neutralizes the metadata harvesting capabilities inherent to legacy platforms and provides a resilient, privacy-maximizing infrastructure tailored for the post-quantum era.

---

<div align="center">

<p>
  <a href="https://simpl.global"><img src="media-logos/btn-simpl-global.svg" alt="Website — simpl.global" height="38" /></a>
  <a href="README.md"><img src="media-logos/btn-readme.svg" alt="README" height="38" /></a>
  <a href="https://simpl.global/donate"><img src="media-logos/btn-donate.svg" alt="Support Zero" height="38" /></a>
</p>

<sub>**© 2026 Simpl.** Zero (`v1.0.0`) is free software licensed under the [GNU Affero General Public License v3.0](LICENSE). · [simpl.global](https://simpl.global) · [Donate](https://simpl.global/donate) · [README](README.md) · [Releases](https://github.com/simpl-hq/zero/releases) · [CHANGELOG](CHANGELOG.md) · [CONTRIBUTING](CONTRIBUTING.md) · `support@simpl.global`</sub>

</div>
