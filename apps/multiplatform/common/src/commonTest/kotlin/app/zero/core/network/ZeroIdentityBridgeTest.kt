package app.zero.core.network

// Unit tests for Kotlin Argon2id PoW vectors and 4-word phrase lookup helpers.

import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class ZeroIdentityBridgeTest {
  @Test
  fun testArgon2idMatchesRfc9106ReferenceVector() {
    val digest = Argon2idPow.hash(
      secret = "127.0.0.1:1700000000:0".toByteArray(Charsets.UTF_8),
      salt = "zerosaltzerosalt".toByteArray(Charsets.UTF_8)
    )
    val hex = digest.joinToString("") { "%02x".format(it) }
    assertEquals("e865d7e3ca51ad3eca56ed38a4847f59", hex.substring(0, 32))
  }

  @Test
  fun testNormalizePhraseAndEphemeralCode() {
    assertEquals(
      "Crimson-Velvet-Horizon-Echo",
      ZeroIdentityBridge.normalizePhrase("  crimson  velvet-horizon echo ")
    )
    assertEquals("482-911", ZeroIdentityBridge.normalizeEphemeralCode("482911"))
    assertEquals("482-911", ZeroIdentityBridge.normalizeEphemeralCode("482-911"))
    assertEquals(
      "abc123xyz",
      ZeroIdentityBridge.extractResolveTarget("https://simpl.global/add/abc123xyz")
    )
    assertFailsWith<IllegalArgumentException> {
      ZeroIdentityBridge.normalizePhrase("only two words")
    }
    assertFailsWith<IllegalArgumentException> {
      ZeroIdentityBridge.normalizeEphemeralCode("12345")
    }
  }

  @Test
  fun testSolveArgon2idPuzzleProducesLeadingZero() = runBlocking {
    val bridge = ZeroIdentityBridge(leadingHexZeros = 1)
    val ip = "127.0.0.1"
    val timestamp = 1700000000L
    val nonce = bridge.solveArgon2idPuzzle(ip, timestamp)
    val digest = Argon2idPow.hash(
      secret = "$ip:$timestamp:$nonce".toByteArray(Charsets.UTF_8),
      salt = "zero-argon2id-pow".toByteArray(Charsets.UTF_8)
    )
    assertTrue((digest[0].toInt() and 0xF0) == 0, "Expected leading 0 hex nibble")
  }
}
