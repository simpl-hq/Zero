package app.zero.core.network

// RFC 9106 Argon2id and BLAKE2b PoW solver aligned with apps/zero-pin-broker parameters (m=8 MiB, t=1, p=1).

internal object Argon2idPow {
  private val BLAKE2B_IV = ulongArrayOf(
    0x6a09e667f3bcc908uL, 0xbb67ae8584caa73buL,
    0x3c6ef372fe94f82buL, 0xa54ff53a5f1d36f1uL,
    0x510e527fade682d1uL, 0x9b05688c2b3e6c1fuL,
    0x1f83d9abfb41bd6buL, 0x5be0cd19137e2179uL
  )

  private val SIGMA = arrayOf(
    intArrayOf(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15),
    intArrayOf(14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3),
    intArrayOf(11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4),
    intArrayOf(7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8),
    intArrayOf(9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13),
    intArrayOf(2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9),
    intArrayOf(12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11),
    intArrayOf(13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10),
    intArrayOf(6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5),
    intArrayOf(10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0),
    intArrayOf(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15),
    intArrayOf(14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3)
  )

  private fun rotr64(x: ULong, n: Int): ULong = (x shr n) or (x shl (64 - n))

  private fun load64LE(b: ByteArray, off: Int): ULong {
    var v = 0uL
    for (i in 0 until 8) {
      v = v or ((b[off + i].toULong() and 0xFFuL) shl (8 * i))
    }
    return v
  }

  private fun store32LE(dst: ByteArray, off: Int, v: Int) {
    dst[off] = (v and 0xFF).toByte()
    dst[off + 1] = ((v ushr 8) and 0xFF).toByte()
    dst[off + 2] = ((v ushr 16) and 0xFF).toByte()
    dst[off + 3] = ((v ushr 24) and 0xFF).toByte()
  }

  private fun store64LE(dst: ByteArray, off: Int, v: ULong) {
    for (i in 0 until 8) {
      dst[off + i] = ((v shr (8 * i)) and 0xFFuL).toByte()
    }
  }

  internal fun blake2b(input: ByteArray, outLen: Int): ByteArray {
    val h = BLAKE2B_IV.copyOf()
    h[0] = h[0] xor (0x01010000uL or outLen.toULong())

    val m = ULongArray(16)
    val v = ULongArray(16)
    val block = ByteArray(128)
    var offset = 0
    var bytesCompressed = 0uL

    fun compress(last: Boolean) {
      for (i in 0 until 16) m[i] = load64LE(block, i * 8)
      for (i in 0 until 8) {
        v[i] = h[i]
        v[i + 8] = BLAKE2B_IV[i]
      }
      v[12] = v[12] xor bytesCompressed
      if (last) v[14] = v[14].inv()

      fun gB(a: Int, b: Int, c: Int, d: Int, x: ULong, y: ULong) {
        v[a] = v[a] + v[b] + x
        v[d] = rotr64(v[d] xor v[a], 32)
        v[c] = v[c] + v[d]
        v[b] = rotr64(v[b] xor v[c], 24)
        v[a] = v[a] + v[b] + y
        v[d] = rotr64(v[d] xor v[a], 16)
        v[c] = v[c] + v[d]
        v[b] = rotr64(v[b] xor v[c], 63)
      }

      for (r in 0 until 12) {
        val s = SIGMA[r]
        gB(0, 4, 8, 12, m[s[0]], m[s[1]])
        gB(1, 5, 9, 13, m[s[2]], m[s[3]])
        gB(2, 6, 10, 14, m[s[4]], m[s[5]])
        gB(3, 7, 11, 15, m[s[6]], m[s[7]])
        gB(0, 5, 10, 15, m[s[8]], m[s[9]])
        gB(1, 6, 11, 12, m[s[10]], m[s[11]])
        gB(2, 7, 8, 13, m[s[12]], m[s[13]])
        gB(3, 4, 9, 14, m[s[14]], m[s[15]])
      }
      for (i in 0 until 8) h[i] = h[i] xor v[i] xor v[i + 8]
    }

    val total = input.size
    if (total == 0) {
      block.fill(0)
      compress(true)
    } else {
      while (offset + 128 < total) {
        System.arraycopy(input, offset, block, 0, 128)
        bytesCompressed += 128uL
        compress(false)
        offset += 128
      }
      val rem = total - offset
      block.fill(0)
      System.arraycopy(input, offset, block, 0, rem)
      bytesCompressed += rem.toULong()
      compress(true)
    }

    val out = ByteArray(outLen)
    for (i in 0 until outLen) {
      out[i] = ((h[i / 8] shr (8 * (i % 8))) and 0xFFuL).toByte()
    }
    return out
  }

  private fun blake2bLong(outLen: Int, data: ByteArray): ByteArray {
    val prefixed = ByteArray(4 + data.size)
    store32LE(prefixed, 0, outLen)
    System.arraycopy(data, 0, prefixed, 4, data.size)
    if (outLen <= 64) return blake2b(prefixed, outLen)

    val out = ByteArray(outLen)
    var v = blake2b(prefixed, 64)
    System.arraycopy(v, 0, out, 0, 32)
    var pos = 32
    var rem = outLen - 32
    while (rem > 64) {
      v = blake2b(v, 64)
      System.arraycopy(v, 0, out, pos, 32)
      pos += 32
      rem -= 32
    }
    val tail = blake2b(v, rem)
    System.arraycopy(tail, 0, out, pos, rem)
    return out
  }

  private fun gArgon(z: ULongArray, a: Int, b: Int, c: Int, d: Int) {
    var va = z[a]; var vb = z[b]; var vc = z[c]; var vd = z[d]
    va += vb + 2uL * (va and 0xFFFFFFFFuL) * (vb and 0xFFFFFFFFuL)
    vd = rotr64(vd xor va, 32)
    vc += vd + 2uL * (vc and 0xFFFFFFFFuL) * (vd and 0xFFFFFFFFuL)
    vb = rotr64(vb xor vc, 24)
    va += vb + 2uL * (va and 0xFFFFFFFFuL) * (vb and 0xFFFFFFFFuL)
    vd = rotr64(vd xor va, 16)
    vc += vd + 2uL * (vc and 0xFFFFFFFFuL) * (vd and 0xFFFFFFFFuL)
    vb = rotr64(vb xor vc, 63)
    z[a] = va; z[b] = vb; z[c] = vc; z[d] = vd
  }

  private fun pStep(z: ULongArray, i0: Int, i1: Int, i2: Int, i3: Int, i4: Int, i5: Int, i6: Int, i7: Int,
                    i8: Int, i9: Int, i10: Int, i11: Int, i12: Int, i13: Int, i14: Int, i15: Int) {
    gArgon(z, i0, i4, i8, i12)
    gArgon(z, i1, i5, i9, i13)
    gArgon(z, i2, i6, i10, i14)
    gArgon(z, i3, i7, i11, i15)
    gArgon(z, i0, i5, i10, i15)
    gArgon(z, i1, i6, i11, i12)
    gArgon(z, i2, i7, i8, i13)
    gArgon(z, i3, i4, i9, i14)
  }

  private fun compressBlocks(x: ULongArray, y: ULongArray, out: ULongArray, r: ULongArray, z: ULongArray) {
    for (i in 0 until 128) {
      val v = x[i] xor y[i]
      r[i] = v
      z[i] = v
    }
    for (i in 0 until 8) {
      val b = 16 * i
      pStep(z, b, b+1, b+2, b+3, b+4, b+5, b+6, b+7, b+8, b+9, b+10, b+11, b+12, b+13, b+14, b+15)
    }
    for (i in 0 until 8) {
      val c = 2 * i
      pStep(z, c, c+1, 16+c, 16+c+1, 32+c, 32+c+1, 48+c, 48+c+1,
            64+c, 64+c+1, 80+c, 80+c+1, 96+c, 96+c+1, 112+c, 112+c+1)
    }
    for (i in 0 until 128) {
      out[i] = r[i] xor z[i]
    }
  }

  private fun bytesToBlock(b: ByteArray): ULongArray {
    val block = ULongArray(128)
    for (i in 0 until 128) block[i] = load64LE(b, i * 8)
    return block
  }

  fun hash(secret: ByteArray, salt: ByteArray, memoryCost: Int = 8192, timeCost: Int = 1, outLen: Int = 32): ByteArray {
    val p = 1
    val v = 0x13
    val y = 2
    val h0In = ByteArray(24 + 4 + secret.size + 4 + salt.size + 8)
    store32LE(h0In, 0, p)
    store32LE(h0In, 4, outLen)
    store32LE(h0In, 8, memoryCost)
    store32LE(h0In, 12, timeCost)
    store32LE(h0In, 16, v)
    store32LE(h0In, 20, y)
    store32LE(h0In, 24, secret.size)
    System.arraycopy(secret, 0, h0In, 28, secret.size)
    val saltOff = 28 + secret.size
    store32LE(h0In, saltOff, salt.size)
    System.arraycopy(salt, 0, h0In, saltOff + 4, salt.size)

    val h0 = blake2b(h0In, 64)
    val blocks = Array(memoryCost) { ULongArray(128) }
    val seedBuf = ByteArray(72)
    System.arraycopy(h0, 0, seedBuf, 0, 64)
    store32LE(seedBuf, 64, 0)
    store32LE(seedBuf, 68, 0)
    blocks[0] = bytesToBlock(blake2bLong(1024, seedBuf))
    store32LE(seedBuf, 64, 1)
    blocks[1] = bytesToBlock(blake2bLong(1024, seedBuf))

    val sl = memoryCost / 4
    val zeroBlock = ULongArray(128)
    val addrInput = ULongArray(128)
    val tmpBlock = ULongArray(128)
    val addrBlock = ULongArray(128)
    val rScratch = ULongArray(128)
    val zScratch = ULongArray(128)
    var prevSlice = -1
    var addrCounter = 0uL

    for (i in 2 until memoryCost) {
      val slice = i / sl
      val idxInSlice = i % sl
      val j1: ULong
      if (slice < 2) {
        if (slice != prevSlice) {
          prevSlice = slice
          addrCounter = 0uL
        }
        if (idxInSlice % 128 == 0 || i == 2) {
          addrCounter += 1uL
          addrInput.fill(0uL)
          addrInput[0] = 0uL
          addrInput[1] = 0uL
          addrInput[2] = slice.toULong()
          addrInput[3] = memoryCost.toULong()
          addrInput[4] = timeCost.toULong()
          addrInput[5] = y.toULong()
          addrInput[6] = addrCounter
          compressBlocks(zeroBlock, addrInput, tmpBlock, rScratch, zScratch)
          compressBlocks(zeroBlock, tmpBlock, addrBlock, rScratch, zScratch)
        }
        j1 = addrBlock[idxInSlice % 128] and 0xFFFFFFFFuL
      } else {
        j1 = blocks[i - 1][0] and 0xFFFFFFFFuL
      }

      val refArea = (i - 1).toULong()
      var rel = (j1 * j1) shr 32
      rel = refArea - 1uL - ((refArea * rel) shr 32)
      compressBlocks(blocks[i - 1], blocks[rel.toInt()], blocks[i], rScratch, zScratch)
    }

    val lastBytes = ByteArray(1024)
    val last = blocks[memoryCost - 1]
    for (i in 0 until 128) store64LE(lastBytes, i * 8, last[i])
    return blake2bLong(outLen, lastBytes)
  }
}
