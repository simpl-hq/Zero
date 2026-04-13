import {
  Decoder, concatBytes,
  encodeWord16, decodeWord16,
  encodeBytes, decodeBytes,
  encodeMaybe,
  decodeLarge, decodeNonEmpty
} from "./encoding.js"
import {sha256} from "../crypto/digest.js"
import {decodePubKeyX25519} from "../crypto/keys.js"
import {blockPad, blockUnpad, XFTP_BLOCK_SIZE} from "./transmission.js"

export interface VersionRange {
  minVersion: number
  maxVersion: number
}

export function encodeVersionRange(vr: VersionRange): Uint8Array {
  return concatBytes(encodeWord16(vr.minVersion), encodeWord16(vr.maxVersion))
}

export function decodeVersionRange(d: Decoder): VersionRange {
  const minVersion = decodeWord16(d)
  const maxVersion = decodeWord16(d)
  if (minVersion > maxVersion) throw new Error("invalid version range: min > max")
  return {minVersion, maxVersion}
}

export function compatibleVRange(a: VersionRange, b: VersionRange): VersionRange | null {
  const min = Math.max(a.minVersion, b.minVersion)
  const max = Math.min(a.maxVersion, b.maxVersion)
  if (min > max) return null
  return {minVersion: min, maxVersion: max}
}

export interface XFTPClientHello {
  webChallenge: Uint8Array | null
}

export function encodeClientHello(hello: XFTPClientHello): Uint8Array {
  const body = encodeMaybe(encodeBytes, hello.webChallenge)
  return hello.webChallenge ? blockPad(body, XFTP_BLOCK_SIZE) : body
}

export interface XFTPClientHandshake {
  xftpVersion: number
  keyHash: Uint8Array
}

export function encodeClientHandshake(ch: XFTPClientHandshake): Uint8Array {
  const body = concatBytes(encodeWord16(ch.xftpVersion), encodeBytes(ch.keyHash))
  return blockPad(body, XFTP_BLOCK_SIZE)
}

export interface XFTPServerHandshake {
  xftpVersionRange: VersionRange
  sessionId: Uint8Array
  certChainDer: Uint8Array[]
  signedKeyDer: Uint8Array
  webIdentityProof: Uint8Array | null
}

export function decodeServerHandshake(block: Uint8Array): XFTPServerHandshake {
  const raw = blockUnpad(block)
  if (raw.length < 20) {
    const text = String.fromCharCode(...raw)
    if (/^[A-Z_]+$/.test(text)) {
      console.error('[XFTP] Server handshake error: %s', text)
      throw new Error("Server handshake error: " + text)
    }
  }
  const d = new Decoder(raw)
  const xftpVersionRange = decodeVersionRange(d)
  const sessionId = decodeBytes(d)
  const certChainDer = decodeNonEmpty(decodeLarge, d)
  const signedKeyDer = decodeLarge(d)
  let webIdentityProof: Uint8Array | null = null
  if (d.remaining() > 0) {
    const sigBytes = decodeBytes(d)
    webIdentityProof = sigBytes.length === 0 ? null : sigBytes
  }
  return {xftpVersionRange, sessionId, certChainDer, signedKeyDer, webIdentityProof}
}

export type ChainCertificates =
  | {type: 'empty'}
  | {type: 'self'; cert: Uint8Array}
  | {type: 'valid'; leafCert: Uint8Array; idCert: Uint8Array; caCert: Uint8Array}
  | {type: 'long'}

export function chainIdCaCerts(certChainDer: Uint8Array[]): ChainCertificates {
  switch (certChainDer.length) {
    case 0: return {type: 'empty'}
    case 1: return {type: 'self', cert: certChainDer[0]}
    case 2: return {type: 'valid', leafCert: certChainDer[0], idCert: certChainDer[1], caCert: certChainDer[1]}
    case 3: return {type: 'valid', leafCert: certChainDer[0], idCert: certChainDer[1], caCert: certChainDer[2]}
    case 4: return {type: 'valid', leafCert: certChainDer[0], idCert: certChainDer[1], caCert: certChainDer[3]}
    default: return {type: 'long'}
  }
}

export function caFingerprint(certChainDer: Uint8Array[]): Uint8Array {
  const cc = chainIdCaCerts(certChainDer)
  if (cc.type !== 'valid') throw new Error("caFingerprint: need valid chain (2-4 certs)")
  return sha256(cc.idCert)
}

export interface SignedKey {
  objectDer: Uint8Array
  dhKey: Uint8Array
  algorithm: Uint8Array
  signature: Uint8Array
}

function derLength(d: Decoder): number {
  const first = d.anyByte()
  if (first < 0x80) return first
  const numBytes = first & 0x7f
  if (numBytes === 0 || numBytes > 4) throw new Error("DER: unsupported length encoding")
  let len = 0
  for (let i = 0; i < numBytes; i++) {
    len = (len << 8) | d.anyByte()
  }
  return len
}

function derElement(d: Decoder): Uint8Array {
  const start = d.offset()
  d.anyByte()
  const len = derLength(d)
  d.take(len)
  return d.buf.subarray(start, d.offset())
}

export function extractSignedKey(signedDer: Uint8Array): SignedKey {
  const outer = new Decoder(signedDer)
  const outerTag = outer.anyByte()
  if (outerTag !== 0x30) throw new Error("SignedExact: expected SEQUENCE tag 0x30, got 0x" + outerTag.toString(16))
  derLength(outer)

  const objectDer = derElement(outer)

  const algorithm = derElement(outer)

  const sigTag = outer.anyByte()
  if (sigTag !== 0x03) throw new Error("SignedExact: expected BIT STRING tag 0x03, got 0x" + sigTag.toString(16))
  const sigLen = derLength(outer)
  const unusedBits = outer.anyByte()
  if (unusedBits !== 0) throw new Error("SignedExact: expected 0 unused bits in signature")
  const signature = outer.take(sigLen - 1)

  const dhKey = decodeX25519Key(objectDer)

  return {objectDer, dhKey, algorithm, signature}
}

function decodeX25519Key(der: Uint8Array): Uint8Array {
  if (der.length === 44) return decodePubKeyX25519(der)
  if (der[0] !== 0x30) throw new Error("decodeX25519Key: expected SEQUENCE")
  const d = new Decoder(der)
  d.anyByte()
  derLength(d)
  const inner = derElement(d)
  return decodePubKeyX25519(inner)
}
