import sodium from "libsodium-wrappers-sumo"
await sodium.ready
import {ed448} from "@noble/curves/ed448"
import {sha256} from "./digest.js"
import {concatBytes} from "../protocol/encoding.js"

export interface Ed25519KeyPair {
  publicKey: Uint8Array
  privateKey: Uint8Array
}

export function generateEd25519KeyPair(): Ed25519KeyPair {
  const kp = sodium.crypto_sign_keypair()
  return {publicKey: kp.publicKey, privateKey: kp.privateKey}
}

export function ed25519KeyPairFromSeed(seed: Uint8Array): Ed25519KeyPair {
  const kp = sodium.crypto_sign_seed_keypair(seed)
  return {publicKey: kp.publicKey, privateKey: kp.privateKey}
}

export interface X25519KeyPair {
  publicKey: Uint8Array
  privateKey: Uint8Array
}

export function generateX25519KeyPair(): X25519KeyPair {
  const kp = sodium.crypto_box_keypair()
  return {publicKey: kp.publicKey, privateKey: kp.privateKey}
}

export function x25519KeyPairFromPrivate(privateKey: Uint8Array): X25519KeyPair {
  const publicKey = sodium.crypto_scalarmult_base(privateKey)
  return {publicKey, privateKey}
}

export function sign(privateKey: Uint8Array, msg: Uint8Array): Uint8Array {
  return sodium.crypto_sign_detached(msg, privateKey)
}

export function verify(publicKey: Uint8Array, sig: Uint8Array, msg: Uint8Array): boolean {
  try {
    return sodium.crypto_sign_verify_detached(sig, msg, publicKey)
  } catch {
    return false
  }
}

export function dh(publicKey: Uint8Array, privateKey: Uint8Array): Uint8Array {
  return sodium.crypto_scalarmult(privateKey, publicKey)
}

const ED25519_PUBKEY_DER_PREFIX = new Uint8Array([
  0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00,
])

const X25519_PUBKEY_DER_PREFIX = new Uint8Array([
  0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x6e, 0x03, 0x21, 0x00,
])

export function encodePubKeyEd25519(rawPubKey: Uint8Array): Uint8Array {
  return concatBytes(ED25519_PUBKEY_DER_PREFIX, rawPubKey)
}

export function decodePubKeyEd25519(der: Uint8Array): Uint8Array {
  if (der.length !== 44) throw new Error("decodePubKeyEd25519: invalid length")
  for (let i = 0; i < ED25519_PUBKEY_DER_PREFIX.length; i++) {
    if (der[i] !== ED25519_PUBKEY_DER_PREFIX[i]) throw new Error("decodePubKeyEd25519: invalid DER prefix")
  }
  return der.subarray(12)
}

export function encodePubKeyX25519(rawPubKey: Uint8Array): Uint8Array {
  return concatBytes(X25519_PUBKEY_DER_PREFIX, rawPubKey)
}

export function decodePubKeyX25519(der: Uint8Array): Uint8Array {
  if (der.length !== 44) throw new Error("decodePubKeyX25519: invalid length")
  for (let i = 0; i < X25519_PUBKEY_DER_PREFIX.length; i++) {
    if (der[i] !== X25519_PUBKEY_DER_PREFIX[i]) throw new Error("decodePubKeyX25519: invalid DER prefix")
  }
  return der.subarray(12)
}

const ED448_PUBKEY_DER_PREFIX = new Uint8Array([
  0x30, 0x43, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x71, 0x03, 0x3a, 0x00,
])

export function encodePubKeyEd448(rawPubKey: Uint8Array): Uint8Array {
  return concatBytes(ED448_PUBKEY_DER_PREFIX, rawPubKey)
}

export function decodePubKeyEd448(der: Uint8Array): Uint8Array {
  if (der.length !== 69) throw new Error("decodePubKeyEd448: invalid length")
  for (let i = 0; i < ED448_PUBKEY_DER_PREFIX.length; i++) {
    if (der[i] !== ED448_PUBKEY_DER_PREFIX[i]) throw new Error("decodePubKeyEd448: invalid DER prefix")
  }
  return der.subarray(12)
}

export function verifyEd448(publicKey: Uint8Array, sig: Uint8Array, msg: Uint8Array): boolean {
  try {
    return ed448.verify(sig, msg, publicKey)
  } catch {
    return false
  }
}

const ED25519_PRIVKEY_DER_PREFIX = new Uint8Array([
  0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x04, 0x22, 0x04, 0x20,
])

const X25519_PRIVKEY_DER_PREFIX = new Uint8Array([
  0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x6e, 0x04, 0x22, 0x04, 0x20,
])

export function encodePrivKeyEd25519(privateKey: Uint8Array): Uint8Array {
  const seed = privateKey.subarray(0, 32)
  return concatBytes(ED25519_PRIVKEY_DER_PREFIX, seed)
}

export function decodePrivKeyEd25519(der: Uint8Array): Uint8Array {
  if (der.length !== 48) throw new Error("decodePrivKeyEd25519: invalid length")
  for (let i = 0; i < ED25519_PRIVKEY_DER_PREFIX.length; i++) {
    if (der[i] !== ED25519_PRIVKEY_DER_PREFIX[i]) throw new Error("decodePrivKeyEd25519: invalid DER prefix")
  }
  return der.subarray(16)
}

export function encodePrivKeyX25519(privateKey: Uint8Array): Uint8Array {
  return concatBytes(X25519_PRIVKEY_DER_PREFIX, privateKey)
}

export function decodePrivKeyX25519(der: Uint8Array): Uint8Array {
  if (der.length !== 48) throw new Error("decodePrivKeyX25519: invalid length")
  for (let i = 0; i < X25519_PRIVKEY_DER_PREFIX.length; i++) {
    if (der[i] !== X25519_PRIVKEY_DER_PREFIX[i]) throw new Error("decodePrivKeyX25519: invalid DER prefix")
  }
  return der.subarray(16)
}

export function keyHash(derPubKey: Uint8Array): Uint8Array {
  return sha256(derPubKey)
}
