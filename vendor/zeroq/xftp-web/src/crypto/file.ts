import {Decoder, concatBytes, encodeInt64, encodeString, decodeString, encodeMaybe, decodeMaybe} from "../protocol/encoding.js"
import {sbInit, sbEncryptChunk, sbDecryptChunk, sbDecryptTailTag, sbAuth} from "./secretbox.js"
import {unPadLazy} from "./padding.js"

const AUTH_TAG_SIZE = 16n
const PROGRESS_SEG = 256 * 1024

export interface FileHeader {
  fileName: string
  fileExtra: string | null
}

export function encodeFileHeader(hdr: FileHeader): Uint8Array {
  return concatBytes(
    encodeString(hdr.fileName),
    encodeMaybe(encodeString, hdr.fileExtra)
  )
}

export function parseFileHeader(data: Uint8Array): {header: FileHeader, rest: Uint8Array} {
  const hdrLen = Math.min(1024, data.length)
  const d = new Decoder(data.subarray(0, hdrLen))
  const fileName = decodeString(d)
  const fileExtra = decodeMaybe(decodeString, d)
  const consumed = d.offset()
  return {
    header: {fileName, fileExtra},
    rest: data.subarray(consumed)
  }
}

export function encryptFile(
  source: Uint8Array,
  fileHdr: Uint8Array,
  key: Uint8Array,
  nonce: Uint8Array,
  fileSize: bigint,
  encSize: bigint,
  onProgress?: (done: number, total: number) => void
): Uint8Array {
  const state = sbInit(key, nonce)
  const lenStr = encodeInt64(fileSize)
  const padLen = Number(encSize - AUTH_TAG_SIZE - fileSize - 8n)
  if (padLen < 0) throw new Error("encryptFile: encSize too small")
  const hdr = sbEncryptChunk(state, concatBytes(lenStr, fileHdr))
  const encSource = new Uint8Array(source.length)
  for (let off = 0; off < source.length; off += PROGRESS_SEG) {
    const end = Math.min(off + PROGRESS_SEG, source.length)
    const seg = sbEncryptChunk(state, source.subarray(off, end))
    encSource.set(seg, off)
    onProgress?.(end, source.length)
  }
  if (source.length === 0) onProgress?.(0, 0)
  const padding = new Uint8Array(padLen)
  padding.fill(0x23)
  const encPad = sbEncryptChunk(state, padding)
  const tag = sbAuth(state)
  return concatBytes(hdr, encSource, encPad, tag)
}

export function decryptChunks(
  encSize: bigint,
  chunks: Uint8Array[],
  key: Uint8Array,
  nonce: Uint8Array,
  onProgress?: (done: number, total: number) => void
): {header: FileHeader, content: Uint8Array} {
  if (chunks.length === 0) throw new Error("decryptChunks: empty chunks")
  const paddedLen = encSize - AUTH_TAG_SIZE
  const data = chunks.length === 1 ? chunks[0] : concatBytes(...chunks)
  if (!onProgress) {
    const {valid, content} = sbDecryptTailTag(key, nonce, paddedLen, data)
    if (!valid) throw new Error("decryptChunks: invalid auth tag")
    const {header, rest} = parseFileHeader(content)
    return {header, content: rest}
  }
  const pLen = Number(paddedLen)
  const cipher = data.subarray(0, pLen)
  const providedTag = data.subarray(pLen)
  const state = sbInit(key, nonce)
  const plaintext = new Uint8Array(pLen)
  for (let off = 0; off < pLen; off += PROGRESS_SEG) {
    const end = Math.min(off + PROGRESS_SEG, pLen)
    const seg = sbDecryptChunk(state, cipher.subarray(off, end))
    plaintext.set(seg, off)
    onProgress(end, pLen)
  }
  if (pLen === 0) onProgress(0, 0)
  const computedTag = sbAuth(state)
  let diff = providedTag.length === 16 ? 0 : 1
  for (let i = 0; i < computedTag.length; i++) diff |= providedTag[i] ^ computedTag[i]
  if (diff !== 0) throw new Error("decryptChunks: invalid auth tag")
  const content = unPadLazy(plaintext)
  const {header, rest} = parseFileHeader(content)
  return {header, content: rest}
}
