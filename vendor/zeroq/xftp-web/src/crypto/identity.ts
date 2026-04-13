import {Decoder, concatBytes} from "../protocol/encoding.js"
import {sha256} from "./digest.js"
import {verify, decodePubKeyEd25519, verifyEd448, decodePubKeyEd448} from "./keys.js"
import {chainIdCaCerts, extractSignedKey} from "../protocol/handshake.js"

function derLen(d: Decoder): number {
  const first = d.anyByte()
  if (first < 0x80) return first
  const n = first & 0x7f
  if (n === 0 || n > 4) throw new Error("DER: unsupported length encoding")
  let len = 0
  for (let i = 0; i < n; i++) len = (len << 8) | d.anyByte()
  return len
}

function derSkip(d: Decoder): void {
  d.anyByte()
  d.take(derLen(d))
}

function derReadElement(d: Decoder): Uint8Array {
  const start = d.offset()
  d.anyByte()
  d.take(derLen(d))
  return d.buf.subarray(start, d.offset())
}

export function extractCertPublicKeyInfo(certDer: Uint8Array): Uint8Array {
  const d = new Decoder(certDer)
  if (d.anyByte() !== 0x30) throw new Error("X.509: expected Certificate SEQUENCE")
  derLen(d)
  if (d.anyByte() !== 0x30) throw new Error("X.509: expected TBSCertificate SEQUENCE")
  derLen(d)
  if (d.buf[d.offset()] === 0xa0) derSkip(d)
  derSkip(d)
  derSkip(d)
  derSkip(d)
  derSkip(d)
  derSkip(d)
  return derReadElement(d)
}

type CertKeyAlgorithm = 'ed25519' | 'ed448'

function detectKeyAlgorithm(spki: Uint8Array): CertKeyAlgorithm {
  if (spki.length === 44 && spki[8] === 0x70) return 'ed25519'
  if (spki.length === 69 && spki[8] === 0x71) return 'ed448'
  throw new Error("unsupported certificate key algorithm")
}

function extractCertRawKey(spki: Uint8Array): {key: Uint8Array, alg: CertKeyAlgorithm} {
  const alg = detectKeyAlgorithm(spki)
  const key = alg === 'ed25519' ? decodePubKeyEd25519(spki) : decodePubKeyEd448(spki)
  return {key, alg}
}

function verifySig(alg: CertKeyAlgorithm, key: Uint8Array, sig: Uint8Array, msg: Uint8Array): boolean {
  return alg === 'ed25519' ? verify(key, sig, msg) : verifyEd448(key, sig, msg)
}

export interface IdentityVerification {
  certChainDer: Uint8Array[]
  signedKeyDer: Uint8Array
  sigBytes: Uint8Array
  challenge: Uint8Array
  sessionId: Uint8Array
  keyHash: Uint8Array
}

export function verifyIdentityProof(v: IdentityVerification): boolean {
  const cc = chainIdCaCerts(v.certChainDer)
  if (cc.type !== 'valid') return false
  const fp = sha256(cc.idCert)
  if (!constantTimeEqual(fp, v.keyHash)) return false
  const spki = extractCertPublicKeyInfo(cc.leafCert)
  const {key, alg} = extractCertRawKey(spki)
  if (!verifySig(alg, key, v.sigBytes, concatBytes(v.challenge, v.sessionId))) return false
  const sk = extractSignedKey(v.signedKeyDer)
  return verifySig(alg, key, sk.signature, sk.objectDer)
}

function constantTimeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false
  let diff = 0
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i]
  return diff === 0
}
