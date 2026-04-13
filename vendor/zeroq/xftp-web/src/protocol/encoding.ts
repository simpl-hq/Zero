
export class Decoder {
  readonly buf: Uint8Array
  private readonly view: DataView
  private pos: number

  constructor(buf: Uint8Array) {
    this.buf = buf
    this.view = new DataView(buf.buffer, buf.byteOffset, buf.byteLength)
    this.pos = 0
  }

  take(n: number): Uint8Array {
    if (this.pos + n > this.buf.length) throw new Error("Decoder: unexpected end of input")
    const slice = this.buf.subarray(this.pos, this.pos + n)
    this.pos += n
    return slice
  }

  takeAll(): Uint8Array {
    const slice = this.buf.subarray(this.pos)
    this.pos = this.buf.length
    return slice
  }

  anyByte(): number {
    if (this.pos >= this.buf.length) throw new Error("Decoder: unexpected end of input")
    return this.buf[this.pos++]
  }

  remaining(): number {
    return this.buf.length - this.pos
  }

  offset(): number {
    return this.pos
  }
}

export function concatBytes(...arrays: Uint8Array[]): Uint8Array {
  let totalLen = 0
  for (const a of arrays) totalLen += a.length
  const result = new Uint8Array(totalLen)
  let offset = 0
  for (const a of arrays) {
    result.set(a, offset)
    offset += a.length
  }
  return result
}

export function encodeWord16(n: number): Uint8Array {
  const buf = new Uint8Array(2)
  const view = new DataView(buf.buffer)
  view.setUint16(0, n, false)
  return buf
}

export function decodeWord16(d: Decoder): number {
  const bytes = d.take(2)
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength)
  return view.getUint16(0, false)
}

export function encodeWord32(n: number): Uint8Array {
  const buf = new Uint8Array(4)
  const view = new DataView(buf.buffer)
  view.setUint32(0, n, false)
  return buf
}

export function decodeWord32(d: Decoder): number {
  const bytes = d.take(4)
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength)
  return view.getUint32(0, false)
}

export function encodeInt64(n: bigint): Uint8Array {
  const high = Number((n >> 32n) & 0xFFFFFFFFn)
  const low = Number(n & 0xFFFFFFFFn)
  return concatBytes(encodeWord32(high), encodeWord32(low))
}

export function decodeInt64(d: Decoder): bigint {
  const high = BigInt(decodeWord32(d))
  const low = BigInt(decodeWord32(d))
  const unsigned = (high << 32n) | low
  return unsigned >= 0x8000000000000000n ? unsigned - 0x10000000000000000n : unsigned
}

export function encodeBytes(bs: Uint8Array): Uint8Array {
  if (bs.length > 255) throw new Error("encodeBytes: length exceeds 255")
  const result = new Uint8Array(1 + bs.length)
  result[0] = bs.length
  result.set(bs, 1)
  return result
}

export function decodeBytes(d: Decoder): Uint8Array {
  const len = d.anyByte()
  return d.take(len)
}

export function encodeLarge(bs: Uint8Array): Uint8Array {
  if (bs.length > 65535) throw new Error("encodeLarge: length exceeds 65535")
  return concatBytes(encodeWord16(bs.length), bs)
}

export function decodeLarge(d: Decoder): Uint8Array {
  const len = decodeWord16(d)
  return d.take(len)
}

export function encodeTail(bs: Uint8Array): Uint8Array {
  return bs
}

export function decodeTail(d: Decoder): Uint8Array {
  return d.takeAll()
}

const CHAR_T = 0x54
const CHAR_F = 0x46

export function encodeBool(b: boolean): Uint8Array {
  return new Uint8Array([b ? CHAR_T : CHAR_F])
}

export function decodeBool(d: Decoder): boolean {
  const byte = d.anyByte()
  if (byte === CHAR_T) return true
  if (byte === CHAR_F) return false
  throw new Error("decodeBool: invalid tag " + byte)
}

const textEncoder = new TextEncoder()
const textDecoder = new TextDecoder()

export function encodeString(s: string): Uint8Array {
  return encodeBytes(textEncoder.encode(s))
}

export function decodeString(d: Decoder): string {
  return textDecoder.decode(decodeBytes(d))
}

const CHAR_0 = 0x30
const CHAR_1 = 0x31

export function encodeMaybe<T>(encode: (v: T) => Uint8Array, v: T | null): Uint8Array {
  if (v === null) return new Uint8Array([CHAR_0])
  return concatBytes(new Uint8Array([CHAR_1]), encode(v))
}

export function decodeMaybe<T>(decode: (d: Decoder) => T, d: Decoder): T | null {
  const tag = d.anyByte()
  if (tag === CHAR_0) return null
  if (tag === CHAR_1) return decode(d)
  throw new Error("decodeMaybe: invalid tag " + tag)
}

export function encodeNonEmpty<T>(encode: (v: T) => Uint8Array, xs: T[]): Uint8Array {
  if (xs.length === 0) throw new Error("encodeNonEmpty: empty list")
  if (xs.length > 255) throw new Error("encodeNonEmpty: length exceeds 255")
  const parts: Uint8Array[] = [new Uint8Array([xs.length])]
  for (const x of xs) parts.push(encode(x))
  return concatBytes(...parts)
}

export function decodeNonEmpty<T>(decode: (d: Decoder) => T, d: Decoder): T[] {
  const len = d.anyByte()
  if (len === 0) throw new Error("decodeNonEmpty: empty list")
  const result: T[] = []
  for (let i = 0; i < len; i++) result.push(decode(d))
  return result
}

export function encodeList<T>(encode: (v: T) => Uint8Array, xs: T[]): Uint8Array {
  if (xs.length > 255) throw new Error("encodeList: length exceeds 255")
  const parts: Uint8Array[] = [new Uint8Array([xs.length])]
  for (const x of xs) parts.push(encode(x))
  return concatBytes(...parts)
}

export function decodeList<T>(decode: (d: Decoder) => T, d: Decoder): T[] {
  const len = d.anyByte()
  const result: T[] = []
  for (let i = 0; i < len; i++) result.push(decode(d))
  return result
}
