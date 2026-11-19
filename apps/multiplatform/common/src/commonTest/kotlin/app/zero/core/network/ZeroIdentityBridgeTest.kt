package app.zero.core.network

// Regression tests for Argon2id invite-bound PoW vectors and 4-word phrase parsing.

import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
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
    val inviteUrl = "zero:/contact#/?v=2-7&smp=smp%3A%2F%2Fzerorelay.simpl.global:5223"
    val timestamp = 1700000000L
    val nonce = bridge.solveArgon2idPuzzle(inviteUrl, timestamp)
    val digest = Argon2idPow.hash(
      secret = "$inviteUrl:$timestamp:$nonce".toByteArray(Charsets.UTF_8),
      salt = "zero-argon2id-pow".toByteArray(Charsets.UTF_8)
    )
    assertTrue((digest[0].toInt() and 0xF0) == 0, "Expected leading 0 hex nibble")
  }

  @Test
  fun testLeadingZeroBitsBoundaryAndResolvedInviteValidation() {
    assertTrue(ZeroIdentityBridge.matchesLeadingZeroBits(byteArrayOf(0x00, 0x3F), 10))
    assertFalse(ZeroIdentityBridge.matchesLeadingZeroBits(byteArrayOf(0x00, 0x40), 10))
    assertTrue(ZeroIdentityBridge.matchesLeadingZeroBits(byteArrayOf(0x00, 0x0F), 12))
    assertFalse(ZeroIdentityBridge.matchesLeadingZeroBits(byteArrayOf(0x00, 0x10), 12))

    val valid = "zero:/contact#/?v=2-7&smp=smp%3A%2F%2Fzerorelay.simpl.global:5223"
    assertEquals(valid, ZeroIdentityBridge.validateResolvedInviteUrl(valid))
    assertFailsWith<IllegalArgumentException> {
      ZeroIdentityBridge.validateResolvedInviteUrl("https://evil.example/phish")
    }
  }

  @Test
  fun testDiscoveryModeParsing() {
    assertEquals(ZeroDiscoveryMode.AIR_GAPPED, ZeroDiscoveryMode.fromConfig("air_gapped"))
    assertEquals(ZeroDiscoveryMode.AIR_GAPPED, ZeroDiscoveryMode.fromConfig("off"))
    assertEquals(ZeroDiscoveryMode.AIR_GAPPED, ZeroDiscoveryMode.fromConfig("disabled"))
    assertEquals(ZeroDiscoveryMode.AIR_GAPPED, ZeroDiscoveryMode.fromConfig("none"))
    assertEquals(ZeroDiscoveryMode.AIR_GAPPED, ZeroDiscoveryMode.fromConfig("direct_only"))
    assertEquals(ZeroDiscoveryMode.AIR_GAPPED, ZeroDiscoveryMode.fromConfig(""))
    assertEquals(ZeroDiscoveryMode.SELF_HOSTED, ZeroDiscoveryMode.fromConfig("https://broker.example.com"))
    assertEquals(ZeroDiscoveryMode.SELF_HOSTED, ZeroDiscoveryMode.fromConfig("self_hosted"))
    assertEquals(ZeroDiscoveryMode.SIMPL_NETWORK, ZeroDiscoveryMode.fromConfig(null))
    assertEquals(ZeroDiscoveryMode.SIMPL_NETWORK, ZeroDiscoveryMode.fromConfig("simpl_network"))
  }
}
