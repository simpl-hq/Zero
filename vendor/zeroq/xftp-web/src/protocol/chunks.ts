import {kb, mb} from "./description.js"
import {sha256} from "../crypto/digest.js"

export const chunkSize0 = kb(64)
export const chunkSize1 = kb(256)
export const chunkSize2 = mb(1)
export const chunkSize3 = mb(4)

export const serverChunkSizes = [chunkSize0, chunkSize1, chunkSize2, chunkSize3]

export const fileSizeLen = 8
export const authTagSize = 16

function size34(sz: number): number {
  return Math.floor((sz * 3) / 4)
}

export function prepareChunkSizes(payloadSize: number): number[] {
  let smallSize: number, bigSize: number
  if (payloadSize > size34(chunkSize3)) {
    smallSize = chunkSize2; bigSize = chunkSize3
  } else if (payloadSize > size34(chunkSize2)) {
    smallSize = chunkSize1; bigSize = chunkSize2
  } else {
    smallSize = chunkSize0; bigSize = chunkSize1
  }
  function prepareSizes(size: number): number[] {
    if (size === 0) return []
    if (size >= bigSize) {
      const n1 = Math.floor(size / bigSize)
      const remSz = size % bigSize
      return new Array<number>(n1).fill(bigSize).concat(prepareSizes(remSz))
    }
    if (size > size34(bigSize)) return [bigSize]
    const n2 = Math.floor(size / smallSize)
    const remSz2 = size % smallSize
    return new Array<number>(remSz2 === 0 ? n2 : n2 + 1).fill(smallSize)
  }
  return prepareSizes(payloadSize)
}

export function singleChunkSize(payloadSize: number): number | null {
  for (const sz of serverChunkSizes) {
    if (payloadSize <= sz) return sz
  }
  return null
}

export interface ChunkSpec {
  chunkOffset: number
  chunkSize: number
}

export function prepareChunkSpecs(chunkSizes: number[]): ChunkSpec[] {
  const specs: ChunkSpec[] = []
  let offset = 0
  for (const size of chunkSizes) {
    specs.push({chunkOffset: offset, chunkSize: size})
    offset += size
  }
  return specs
}

export function getChunkDigest(chunk: Uint8Array): Uint8Array {
  return sha256(chunk)
}
