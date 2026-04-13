import {encodeWord16, decodeWord16, encodeInt64, decodeInt64, Decoder} from "../protocol/encoding.js"

const HASH = 0x23

export function pad(msg: Uint8Array, paddedLen: number): Uint8Array {
  const len = msg.length
  if (len > 65535) throw new Error("pad: message too large for Word16 length")
  const fillLen = paddedLen - len - 2
  if (fillLen < 0) throw new Error("pad: message exceeds padded size")
  const result = new Uint8Array(paddedLen)
  const lenBytes = encodeWord16(len)
  result.set(lenBytes, 0)
  result.set(msg, 2)
  result.fill(HASH, 2 + len)
  return result
}

export function unPad(padded: Uint8Array): Uint8Array {
  if (padded.length < 2) throw new Error("unPad: input too short")
  const d = new Decoder(padded)
  const len = decodeWord16(d)
  if (padded.length - 2 < len) throw new Error("unPad: invalid length")
  return padded.subarray(2, 2 + len)
}

export function padLazy(msg: Uint8Array, msgLen: bigint, padLen: bigint): Uint8Array {
  const fillLen = padLen - msgLen - 8n
  if (fillLen < 0n) throw new Error("padLazy: message exceeds padded size")
  const totalLen = Number(padLen)
  const result = new Uint8Array(totalLen)
  const lenBytes = encodeInt64(msgLen)
  result.set(lenBytes, 0)
  result.set(msg.subarray(0, Number(msgLen)), 8)
  result.fill(HASH, 8 + Number(msgLen))
  return result
}

export function unPadLazy(padded: Uint8Array): Uint8Array {
  return splitLen(padded).content
}

export function splitLen(data: Uint8Array): {len: bigint; content: Uint8Array} {
  if (data.length < 8) throw new Error("splitLen: input too short")
  const d = new Decoder(data)
  const len = decodeInt64(d)
  if (len < 0n) throw new Error("splitLen: negative length")
  const numLen = Number(len)
  const available = data.length - 8
  const takeLen = Math.min(numLen, available)
  return {len, content: data.subarray(8, 8 + takeLen)}
}
