import {
  Decoder, concatBytes,
  encodeBytes, decodeBytes,
  encodeLarge, decodeLarge
} from "./encoding.js"
import {sign} from "../crypto/keys.js"

export const XFTP_BLOCK_SIZE = 16384

export const initialXFTPVersion = 1
export const authCmdsXFTPVersion = 2
export const blockedFilesXFTPVersion = 3
export const currentXFTPVersion = 3

export function blockPad(msg: Uint8Array, blockSize: number = XFTP_BLOCK_SIZE): Uint8Array {
  const len = msg.length
  const padLen = blockSize - len - 2
  if (padLen < 0) throw new Error("blockPad: message too large for block")
  const result = new Uint8Array(blockSize)
  result[0] = (len >>> 8) & 0xff
  result[1] = len & 0xff
  result.set(msg, 2)
  result.fill(0x23, 2 + len)
  return result
}

export function blockUnpad(block: Uint8Array): Uint8Array {
  if (block.length < 2) throw new Error("blockUnpad: too short")
  const len = (block[0] << 8) | block[1]
  if (2 + len > block.length) throw new Error("blockUnpad: invalid length")
  return block.subarray(2, 2 + len)
}

export function encodeAuthTransmission(
  sessionId: Uint8Array,
  corrId: Uint8Array,
  entityId: Uint8Array,
  cmdBytes: Uint8Array,
  privateKey: Uint8Array
): Uint8Array {
  const tInner = concatBytes(encodeBytes(corrId), encodeBytes(entityId), cmdBytes)
  const tForAuth = concatBytes(encodeBytes(sessionId), tInner)
  const signature = sign(privateKey, tForAuth)
  const authenticator = encodeBytes(signature)
  const encoded = concatBytes(authenticator, tForAuth)
  const batch = concatBytes(new Uint8Array([1]), encodeLarge(encoded))
  return blockPad(batch)
}

export function encodeTransmission(
  sessionId: Uint8Array,
  corrId: Uint8Array,
  entityId: Uint8Array,
  cmdBytes: Uint8Array
): Uint8Array {
  const tInner = concatBytes(encodeBytes(sessionId), encodeBytes(corrId), encodeBytes(entityId), cmdBytes)
  const authenticator = encodeBytes(new Uint8Array(0))
  const encoded = concatBytes(authenticator, tInner)
  const batch = concatBytes(new Uint8Array([1]), encodeLarge(encoded))
  return blockPad(batch)
}

export interface DecodedTransmission {
  corrId: Uint8Array
  entityId: Uint8Array
  command: Uint8Array
}

export function decodeTransmission(sessionId: Uint8Array, block: Uint8Array): DecodedTransmission {
  const raw = blockUnpad(block)
  const d = new Decoder(raw)
  const count = d.anyByte()
  if (count !== 1) throw new Error("decodeTransmission: expected batch count 1, got " + count)
  const transmission = decodeLarge(d)
  const td = new Decoder(transmission)
  decodeBytes(td)
  const sessId = decodeBytes(td)
  if (sessId.length !== sessionId.length || !sessId.every((b, i) => b === sessionId[i])) {
    console.error('[XFTP] Session ID mismatch in server response')
    throw new Error("Session ID mismatch in server response")
  }
  const corrId = decodeBytes(td)
  const entityId = decodeBytes(td)
  const command = td.takeAll()
  return {corrId, entityId, command}
}
