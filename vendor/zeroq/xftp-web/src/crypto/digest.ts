import sodium from "libsodium-wrappers-sumo"

export function sha256(data: Uint8Array): Uint8Array {
  return sodium.crypto_hash_sha256(data)
}

export function sha512(data: Uint8Array): Uint8Array {
  return sodium.crypto_hash_sha512(data)
}

export function sha512Streaming(
  chunks: Iterable<Uint8Array>,
  onProgress?: (done: number, total: number) => void,
  totalBytes?: number
): Uint8Array {
  const SEG = 4 * 1024 * 1024
  const state = sodium.crypto_hash_sha512_init() as unknown as sodium.StateAddress
  let done = 0
  for (const chunk of chunks) {
    for (let off = 0; off < chunk.length; off += SEG) {
      const end = Math.min(off + SEG, chunk.length)
      sodium.crypto_hash_sha512_update(state, chunk.subarray(off, end))
      done += end - off
      onProgress?.(done, totalBytes ?? done)
    }
  }
  return sodium.crypto_hash_sha512_final(state)
}
