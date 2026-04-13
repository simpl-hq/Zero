import {dh} from "./crypto/keys.js"
import {sha256} from "./crypto/digest.js"
import {decryptChunks, type FileHeader} from "./crypto/file.js"
import {decryptTransportChunk} from "./protocol/client.js"
import type {FileDescription} from "./protocol/description.js"

export function processFileResponse(
  recipientPrivKey: Uint8Array,
  serverDhKey: Uint8Array,
): Uint8Array {
  return dh(serverDhKey, recipientPrivKey)
}

export function decryptReceivedChunk(
  dhSecret: Uint8Array,
  cbNonce: Uint8Array,
  encData: Uint8Array,
  expectedDigest: Uint8Array | null
): Uint8Array {
  const providedTag = encData.slice(encData.length - 16)
  const {valid, content} = decryptTransportChunk(dhSecret, cbNonce, encData)
  if (!valid) throw new Error("transport auth tag verification failed")
  if (expectedDigest !== null) {
    const actual = sha256(content)
    if (!digestEqual(actual, expectedDigest)) {
      throw new Error("chunk digest mismatch")
    }
  }
  return content
}

export function processDownloadedFile(
  fd: FileDescription,
  plaintextChunks: Uint8Array[]
): {header: FileHeader, content: Uint8Array} {
  return decryptChunks(BigInt(fd.size), plaintextChunks, fd.key, fd.nonce)
}

function digestEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false
  let diff = 0
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i]
  return diff === 0
}
