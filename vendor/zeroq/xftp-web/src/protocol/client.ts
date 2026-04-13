import {concatBytes} from "./encoding.js"
import {dh} from "../crypto/keys.js"
import {sha512} from "../crypto/digest.js"
import {
  cbInit, sbEncryptChunk, sbDecryptChunk, sbAuth, cryptoBox
} from "../crypto/secretbox.js"

export const cbAuthenticatorSize = 80

export function cbAuthenticate(
  peerPubKey: Uint8Array,
  ownPrivKey: Uint8Array,
  nonce: Uint8Array,
  msg: Uint8Array
): Uint8Array {
  const dhSecret = dh(peerPubKey, ownPrivKey)
  const hash = sha512(msg)
  return cryptoBox(dhSecret, nonce, hash)
}

export function cbVerify(
  peerPubKey: Uint8Array,
  ownPrivKey: Uint8Array,
  nonce: Uint8Array,
  authenticator: Uint8Array,
  msg: Uint8Array
): boolean {
  if (authenticator.length !== cbAuthenticatorSize) return false
  const dhSecret = dh(peerPubKey, ownPrivKey)
  const tag = authenticator.subarray(0, 16)
  const cipher = authenticator.subarray(16)
  const state = cbInit(dhSecret, nonce)
  const plaintext = sbDecryptChunk(state, cipher)
  const computedTag = sbAuth(state)
  if (!constantTimeEqual(tag, computedTag)) return false
  const expectedHash = sha512(msg)
  return constantTimeEqual(plaintext, expectedHash)
}

export function encryptTransportChunk(
  dhSecret: Uint8Array,
  cbNonce: Uint8Array,
  plainData: Uint8Array
): Uint8Array {
  const state = cbInit(dhSecret, cbNonce)
  const cipher = sbEncryptChunk(state, plainData)
  const tag = sbAuth(state)
  return concatBytes(cipher, tag)
}

export function decryptTransportChunk(
  dhSecret: Uint8Array,
  cbNonce: Uint8Array,
  encData: Uint8Array
): {valid: boolean, content: Uint8Array, computedTag: Uint8Array} {
  if (encData.length < 16) return {valid: false, content: new Uint8Array(0), computedTag: new Uint8Array(0)}
  const cipher = encData.subarray(0, encData.length - 16)
  const providedTag = encData.subarray(encData.length - 16)
  const state = cbInit(dhSecret, cbNonce)
  const plaintext = sbDecryptChunk(state, cipher)
  const computedTag = sbAuth(state)
  const valid = constantTimeEqual(providedTag, computedTag)
  return {valid, content: plaintext, computedTag}
}

function constantTimeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false
  let diff = 0
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i]
  return diff === 0
}
