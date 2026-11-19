package app.zero.core.network

// Broker client for 4-word phrase provisioning, ephemeral 6-digit pairing codes, invite-bound Argon2id PoW, and TURN tokens.

import app.zero.core.common.model.ChatController.appPrefs
import app.zero.core.common.views.call.RTCIceServer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.URL
import java.security.MessageDigest
import java.security.cert.X509Certificate
import java.util.Base64
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLPeerUnverifiedException
import kotlin.coroutines.coroutineContext

data class ZeroPhraseIdentity(
  val phrase: String,
  val deepLink: String,
  val slug: String
)

data class ZeroEphemeralCode(
  val code: String,
  val expiresInSeconds: Int
)

enum class ZeroDiscoveryMode(val id: String, val title: String, val description: String) {
  SIMPL_NETWORK(
    "simpl_network",
    "Simpl Network (Default)",
    "Encrypted rendezvous via pinned zeroapi/zeroeu/zerona.simpl.global cluster."
  ),
  SELF_HOSTED(
    "self_hosted",
    "Self-Hosted Broker",
    "Route discovery exclusively to your verified HTTPS endpoint with zero silent fallback."
  ),
  AIR_GAPPED(
    "air_gapped",
    "Air-Gapped / Direct Only",
    "Completely disable broker network activity. Exchange contacts via direct QR or 1-time links."
  );

  companion object {
    fun fromConfig(configured: String?): ZeroDiscoveryMode {
      val trimmed = configured?.trim()?.lowercase() ?: return SIMPL_NETWORK
      return when {
        trimmed in setOf("air_gapped", "airgapped", "direct_only", "off", "disabled", "none", "") -> AIR_GAPPED
        trimmed.startsWith("https://") || trimmed == "self_hosted" || trimmed == "custom" -> SELF_HOSTED
        else -> SIMPL_NETWORK
      }
    }
  }
}

class ZeroIdentityBridge(
  private val directoryUrl: String = DEFAULT_DIRECTORY_URL,
  private val leadingHexZeros: Int? = null,
  private val leadingZeroBits: Int = leadingHexZeros?.let { it * 4 } ?: DEFAULT_POW_ZERO_BITS
) {
  companion object {
    const val DEFAULT_DIRECTORY_URL = "https://zeroapi.simpl.global"
    private val SIMPL_BROKER_HOSTS = setOf(
      "zeroapi.simpl.global",
      "zeroeu.simpl.global",
      "zerona.simpl.global"
    )
    private val FALLBACK_DIRECTORY_URLS = listOf(
      "https://zeroapi.simpl.global",
      "https://zeroeu.simpl.global",
      "https://zerona.simpl.global"
    )
    // Verified CA SPKI SHA-256 pins (ISRG Root X2, Root YE, Let's Encrypt YE1/YE2) — survives 90-day leaf cert renewal while blocking rogue CAs.
    private val SIMPL_BROKER_SPKI_PINS = setOf(
      "diGVwiVYbubAI3RW4hB9xU8e/CH2GnkuvVFZE8zmgzI=",
      "sCkq5UWXjg+7mKu9lMhhYF5bGLsy7VI/UNW3tccdR7w=",
      "brzvtCELCIZUo4sD/qPX0ccRtPsd3DY6RfmxpOU9oB4=",
      "s/tdAOmUzd8syaTuqfgGvFcn6DzA5Cmb+Vby1ST+U3Y="
    )
    const val DEEP_LINK_PREFIX = "https://simpl.global/add/"
    const val DEFAULT_POW_HEX_ZEROS = 2
    const val DEFAULT_POW_ZERO_BITS = 10
    private val ARGON2_SALT = "zero-argon2id-pow".toByteArray(Charsets.UTF_8)
    private const val MAX_SOLVER_ITERATIONS = 100_000L
    private const val CONNECT_TIMEOUT_MS = 8_000
    private const val READ_TIMEOUT_MS = 8_000
    private const val MASKED_USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"

    private val EPHEMERAL_DIGITS_REGEX = Regex("^\\d{6}$")
    private val PHRASE_REGEX = Regex("^[a-zA-Z]+-[a-zA-Z]+-[a-zA-Z]+-[a-zA-Z]+$")

    fun normalizePhrase(input: String): String {
      val tokens = input.trim().split(Regex("[\\s\\-]+")).filter { it.isNotBlank() }
      require(tokens.size == 4 && tokens.all { token -> token.all { it.isLetter() } }) {
        "Phrase must contain exactly 4 words (e.g. Crimson-Velvet-Horizon-Echo)"
      }
      return tokens.joinToString("-") { w ->
        w.lowercase().replaceFirstChar { it.uppercaseChar() }
      }
    }

    fun normalizeEphemeralCode(input: String): String {
      val digitsOnly = input.filter { it.isDigit() }
      require(EPHEMERAL_DIGITS_REGEX.matches(digitsOnly)) {
        "In-person code must contain exactly 6 digits (e.g. 482-911)"
      }
      return "${digitsOnly.substring(0, 3)}-${digitsOnly.substring(3, 6)}"
    }

    fun extractResolveTarget(rawInput: String): String {
      val trimmed = rawInput.trim()
      if (trimmed.startsWith(DEEP_LINK_PREFIX, ignoreCase = true)) {
        return trimmed.substring(DEEP_LINK_PREFIX.length).trim('/')
      }
      val digits = trimmed.filter { it.isDigit() }
      if (EPHEMERAL_DIGITS_REGEX.matches(digits)) {
        return "${digits.substring(0, 3)}-${digits.substring(3, 6)}"
      }
      val normalizedWords = trimmed.split(Regex("[\\s\\-]+")).filter { it.isNotBlank() }
      if (normalizedWords.size == 4 && normalizedWords.all { w -> w.all { it.isLetter() } }) {
        return normalizedWords.joinToString("-") { it.lowercase() }
      }
      return trimmed
    }

    internal fun matchesLeadingZeroBits(digestBytes: ByteArray, zeroBits: Int): Boolean {
      if (zeroBits <= 0) return true
      val fullZeroBytes = zeroBits / 8
      if (fullZeroBytes >= digestBytes.size) return false
      for (i in 0 until fullZeroBytes) {
        if (digestBytes[i].toInt() != 0) return false
      }
      val remBits = zeroBits % 8
      if (remBits > 0) {
        val mask = (0xFF shl (8 - remBits)) and 0xFF
        if ((digestBytes[fullZeroBytes].toInt() and mask) != 0) return false
      }
      return true
    }

    internal fun matchesLeadingHexZeros(digestBytes: ByteArray, hexZeros: Int): Boolean =
      matchesLeadingZeroBits(digestBytes, hexZeros * 4)

    internal fun validateResolvedInviteUrl(inviteUrl: String): String {
      val cleanInvite = inviteUrl.trim()
      require(cleanInvite.startsWith("zero:/") && cleanInvite.none { it.isISOControl() }) {
        "Resolved invite URI must use zero:/ scheme"
      }
      return cleanInvite
    }
  }

  internal suspend fun solveArgon2idPuzzle(inviteUrl: String, time: Long): String = withContext(Dispatchers.Default) {
    require(inviteUrl.isNotBlank() && inviteUrl.length <= 4096) { "Invalid invite context for PoW" }
    var nonce = 0L
    while (nonce < MAX_SOLVER_ITERATIONS) {
      coroutineContext.ensureActive()
      val secret = "$inviteUrl:$time:$nonce".toByteArray(Charsets.UTF_8)
      val hash = Argon2idPow.hash(secret, ARGON2_SALT)
      if (matchesLeadingZeroBits(hash, leadingZeroBits)) {
        return@withContext nonce.toString()
      }
      nonce++
    }
    throw IllegalStateException("Argon2id Proof-of-Work solver exceeded iteration budget")
  }

  private fun candidateBaseUrls(): List<String> {
    val configured = runCatching { appPrefs.zeroDirectoryUrl.get() }.getOrNull()?.trim()
    val mode = ZeroDiscoveryMode.fromConfig(configured)
    return when (mode) {
      ZeroDiscoveryMode.AIR_GAPPED -> emptyList()
      ZeroDiscoveryMode.SELF_HOSTED -> {
        if (configured != null && configured.startsWith("https://", ignoreCase = true)) {
          val host = runCatching { URL(configured).host.lowercase() }.getOrNull()
          if (!host.isNullOrEmpty() && host !in SIMPL_BROKER_HOSTS) {
            listOf(configured.trimEnd('/'))
          } else {
            // Strictly zero silent fallback to simpl.global if self-hosted endpoint is invalid
            emptyList()
          }
        } else {
          emptyList()
        }
      }
      ZeroDiscoveryMode.SIMPL_NETWORK -> {
        (listOfNotNull(
          configured?.takeIf { it.startsWith("https://", ignoreCase = true) },
          directoryUrl.takeIf { it.startsWith("https://", ignoreCase = true) }
        ) + FALLBACK_DIRECTORY_URLS).map { it.trimEnd('/') }.distinct()
      }
    }
  }

  private fun cacheIdentityLocally(key: String, inviteUrl: String) {
    runCatching {
      val current = appPrefs.zeroPinCache.get().toMutableMap()
      current[key] = inviteUrl
      appPrefs.zeroPinCache.set(current)
      if (PHRASE_REGEX.matches(key)) {
        appPrefs.zeroAccountPin.set(key)
      }
    }
  }

  private fun validateInviteUrl(inviteUrl: String): String {
    val cleanInvite = inviteUrl.trim()
    require(
      (cleanInvite.startsWith("zero:/") || cleanInvite.startsWith("https://")) &&
        cleanInvite.none { it.isISOControl() }
    ) {
      "Invalid cryptographic invite URL"
    }
    return cleanInvite
  }

  suspend fun provisionPhraseAndDeepLink(
    localCryptoInviteUrl: String
  ): ZeroPhraseIdentity = withContext(Dispatchers.IO) {
    val cleanInvite = validateInviteUrl(localCryptoInviteUrl)
    val timestamp = System.currentTimeMillis() / 1000
    val verifiedNonce = solveArgon2idPuzzle(cleanInvite, timestamp)

    val payload = buildJsonObject {
      put("invite_url", cleanInvite)
      put("nonce", verifiedNonce)
      put("timestamp", timestamp)
    }.toString()

    val bases = candidateBaseUrls()
    if (bases.isEmpty()) {
      throw IllegalStateException("Contact discovery broker is disabled; share a direct QR or 1-time link.")
    }

    var lastError: Throwable? = null
    for (base in bases) {
      try {
        val responseText = executeHttpRequest(
          url = "$base/api/v1/identity/phrase",
          method = "POST",
          body = payload
        )
        val json = Json.parseToJsonElement(responseText).jsonObject
        val phrase = json["phrase"]?.jsonPrimitive?.content
        val deepLink = json["deep_link"]?.jsonPrimitive?.content
        val slug = json["slug"]?.jsonPrimitive?.content
        if (!phrase.isNullOrBlank() && !deepLink.isNullOrBlank() && !slug.isNullOrBlank()) {
          val normalized = normalizePhrase(phrase)
          cacheIdentityLocally(normalized, cleanInvite)
          cacheIdentityLocally(slug, cleanInvite)
          return@withContext ZeroPhraseIdentity(normalized, deepLink, slug)
        }
      } catch (e: Throwable) {
        lastError = e
      }
    }

    throw IllegalStateException("Directory relay unreachable for phrase provisioning", lastError)
  }

  suspend fun provisionEphemeral6DigitCode(
    localCryptoInviteUrl: String
  ): ZeroEphemeralCode = withContext(Dispatchers.IO) {
    val cleanInvite = validateInviteUrl(localCryptoInviteUrl)
    val timestamp = System.currentTimeMillis() / 1000
    val verifiedNonce = solveArgon2idPuzzle(cleanInvite, timestamp)

    val payload = buildJsonObject {
      put("invite_url", cleanInvite)
      put("nonce", verifiedNonce)
      put("timestamp", timestamp)
    }.toString()

    val bases = candidateBaseUrls()
    if (bases.isEmpty()) {
      throw IllegalStateException("Contact discovery broker is disabled; share a direct QR or 1-time link.")
    }

    var lastError: Throwable? = null
    for (base in bases) {
      try {
        val responseText = executeHttpRequest(
          url = "$base/api/v1/identity/ephemeral",
          method = "POST",
          body = payload
        )
        val json = Json.parseToJsonElement(responseText).jsonObject
        val code = json["code"]?.jsonPrimitive?.content
        val ttl = json["expires_in"]?.jsonPrimitive?.intOrNull ?: 300
        if (!code.isNullOrBlank()) {
          val normalized = normalizeEphemeralCode(code)
          cacheIdentityLocally(normalized, cleanInvite)
          return@withContext ZeroEphemeralCode(normalized, ttl)
        }
      } catch (e: Throwable) {
        lastError = e
      }
    }

    throw IllegalStateException("Directory relay unreachable for ephemeral code provisioning", lastError)
  }

  suspend fun resolveIdentity(rawTarget: String): String = withContext(Dispatchers.IO) {
    val target = extractResolveTarget(rawTarget)
    val bases = candidateBaseUrls()
    var lastError: Throwable? = if (bases.isEmpty()) {
      IllegalStateException("Contact discovery broker is disabled; share a direct QR or 1-time link.")
    } else null
    for (base in bases) {
      try {
        val responseText = executeHttpRequest(
          url = "$base/api/v1/identity/resolve/$target",
          method = "GET",
          body = null
        )
        val json = Json.parseToJsonElement(responseText).jsonObject
        val inviteUrl = json["invite_url"]?.jsonPrimitive?.content
        if (!inviteUrl.isNullOrBlank()) {
          return@withContext validateResolvedInviteUrl(inviteUrl)
        }
      } catch (e: Throwable) {
        lastError = e
      }
    }

    val cached = runCatching {
      val map = appPrefs.zeroPinCache.get()
      map[target] ?: map[normalizePhrase(rawTarget)]
    }.getOrNull()
    if (!cached.isNullOrBlank()) {
      return@withContext validateResolvedInviteUrl(cached)
    }

    throw lastError ?: IllegalStateException("Identity could not be resolved")
  }

  suspend fun fetchEphemeralTurnServers(): List<RTCIceServer>? = withContext(Dispatchers.IO) {
    for (base in candidateBaseUrls()) {
      try {
        val responseText = executeHttpRequest(
          url = "$base/api/v1/turn/credentials",
          method = "GET",
          body = null
        )
        val json = Json.parseToJsonElement(responseText).jsonObject
        val username = json["username"]?.jsonPrimitive?.content ?: continue
        val credential = json["credential"]?.jsonPrimitive?.content ?: continue
        val uris = json["uris"]?.jsonArray?.mapNotNull { it.jsonPrimitive.content } ?: continue
        val stunUris = uris.filter { it.startsWith("stun:") || it.startsWith("stuns:") }
        val turnUris = uris.filter { it.startsWith("turn:") || it.startsWith("turns:") }
        val servers = mutableListOf<RTCIceServer>()
        if (stunUris.isNotEmpty()) {
          servers.add(RTCIceServer(urls = stunUris))
        }
        if (turnUris.isNotEmpty()) {
          servers.add(RTCIceServer(urls = turnUris, username = username, credential = credential))
        }
        if (servers.isNotEmpty()) return@withContext servers
      } catch (_: Throwable) {
      }
    }
    null
  }

  private fun verifyBrokerTlsPins(conn: HttpURLConnection, url: URL) {
    if (!url.protocol.equals("https", ignoreCase = true)) {
      throw SSLPeerUnverifiedException("Plaintext HTTP rejected for broker host ${url.host}")
    }
    val host = url.host.lowercase()
    if (host !in SIMPL_BROKER_HOSTS) return
    val httpsConn = conn as? HttpsURLConnection
      ?: throw SSLPeerUnverifiedException("Expected HTTPS connection for $host")
    val sha256 = MessageDigest.getInstance("SHA-256")
    val matched = httpsConn.serverCertificates.any { cert ->
      val x509 = cert as? X509Certificate ?: return@any false
      val spkiPin = Base64.getEncoder().encodeToString(sha256.digest(x509.publicKey.encoded))
      spkiPin in SIMPL_BROKER_SPKI_PINS
    }
    if (!matched) {
      throw SSLPeerUnverifiedException("Broker TLS SPKI pin verification failed for $host")
    }
  }

  private fun executeHttpRequest(url: String, method: String, body: String?): String {
    val parsedUrl = URL(url)
    val proxy = resolveActiveSocksProxy()
    val conn = (if (proxy != null) parsedUrl.openConnection(proxy) else parsedUrl.openConnection()) as HttpURLConnection
    conn.instanceFollowRedirects = false
    conn.connectTimeout = CONNECT_TIMEOUT_MS
    conn.readTimeout = READ_TIMEOUT_MS
    conn.requestMethod = method
    conn.setRequestProperty("User-Agent", MASKED_USER_AGENT)
    conn.setRequestProperty("Accept", "application/json")
    conn.setRequestProperty("Cache-Control", "no-store")
    try {
      if (body != null) {
        conn.doOutput = true
        conn.setRequestProperty("Content-Type", "application/json; charset=utf-8")
        conn.connect()
        verifyBrokerTlsPins(conn, parsedUrl)
        OutputStreamWriter(conn.outputStream, Charsets.UTF_8).use { writer ->
          writer.write(body)
          writer.flush()
        }
      } else {
        conn.connect()
        verifyBrokerTlsPins(conn, parsedUrl)
      }
      val code = conn.responseCode
      val stream = if (code in 200..299) conn.inputStream else conn.errorStream
      val text = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() } ?: ""
      if (code !in 200..299) {
        throw IllegalStateException("Directory HTTP $code: $text")
      }
      return text
    } finally {
      conn.disconnect()
    }
  }

  fun hasActiveProxy(): Boolean = resolveActiveSocksProxy() != null

  private fun resolveActiveSocksProxy(): Proxy? {
    val useSocks = runCatching { appPrefs.networkUseSocksProxy.get() }.getOrDefault(false)
    if (!useSocks) return null
    val netProxy = try {
      appPrefs.networkProxy.get()
    } catch (t: Throwable) {
      throw IllegalStateException("SOCKS5 proxy enabled but configuration could not be read", t)
    }
    val host = netProxy.host.trim().ifBlank { "localhost" }
    val port = netProxy.port
    if (port !in 1..65535) {
      throw IllegalStateException("SOCKS5 proxy enabled with invalid port: $port")
    }
    return Proxy(Proxy.Type.SOCKS, InetSocketAddress(host, port))
  }
}
