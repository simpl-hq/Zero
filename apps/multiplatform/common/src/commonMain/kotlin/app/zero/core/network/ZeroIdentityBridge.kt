package app.zero.core.network

// Client bridge for the pin broker API, PoW solving, and ephemeral TURN credentials.

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
import java.security.SecureRandom
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

class ZeroIdentityBridge(
  private val directoryUrl: String = DEFAULT_DIRECTORY_URL,
  private val leadingHexZeros: Int = DEFAULT_POW_HEX_ZEROS
) {
  companion object {
    const val DEFAULT_DIRECTORY_URL = "https://zeroapi.simpl.global"
    const val DEEP_LINK_PREFIX = "https://simpl.global/add/"
    const val DEFAULT_POW_HEX_ZEROS = 1
    private val ARGON2_SALT = "zero-argon2id-pow".toByteArray(Charsets.UTF_8)
    private const val MAX_SOLVER_ITERATIONS = 50_000L
    private const val CONNECT_TIMEOUT_MS = 8_000
    private const val READ_TIMEOUT_MS = 8_000
    private const val MASKED_USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"

    private val EPHEMERAL_DIGITS_REGEX = Regex("^\\d{6}$")
    private val PHRASE_REGEX = Regex("^[a-zA-Z]+-[a-zA-Z]+-[a-zA-Z]+-[a-zA-Z]+$")

    private val FALLBACK_WORDS = arrayOf(
      "Acorn", "Amber", "Anchor", "Anvil", "Apex", "Arbor", "Arctic", "Arrow",
      "Aspen", "Atlas", "Aurora", "Autumn", "Azure", "Beacon", "Birch", "Blaze",
      "Boulder", "Breeze", "Bridge", "Brook", "Canyon", "Carbon", "Cedar", "Cipher",
      "Cloud", "Cobalt", "Comet", "Copper", "Coral", "Cosmos", "Crest", "Crimson",
      "Crystal", "Cypress", "Dawn", "Delta", "Diamond", "Drift", "Dune", "Echo",
      "Eclipse", "Ember", "Emerald", "Falcon", "Feather", "Fjord", "Flame", "Flint",
      "Forest", "Forge", "Frost", "Galaxy", "Garnet", "Glacier", "Glade", "Granite",
      "Harbor", "Hawk", "Heather", "Helix", "Horizon", "Indigo", "Iron", "Island",
      "Ivory", "Jade", "Jasper", "Juniper", "Kestrel", "Lagoon", "Lantern", "Laurel",
      "Lotus", "Lunar", "Lynx", "Magnet", "Maple", "Marble", "Meadow", "Mercury",
      "Meteor", "Mirror", "Mist", "Monarch", "Moon", "Nebula", "Nimbus", "Noble",
      "North", "Nova", "Oak", "Oasis", "Obsidian", "Ocean", "Onyx", "Opal",
      "Orbit", "Orchid", "Osprey", "Otter", "Ozone", "Panther", "Pebble", "Phantom",
      "Phoenix", "Pine", "Planet", "Polar", "Prism", "Quartz", "Quill", "Rain",
      "Raven", "Redwood", "Reef", "Ridge", "Ripple", "River", "Rocket", "Ruby",
      "Sable", "Saffron", "Sage", "Sapphire", "Scarlet", "Sequoia", "Shadow", "Shield",
      "Sierra", "Silver", "Slate", "Snow", "Solar", "Solstice", "Spark", "Specter",
      "Sphere", "Spruce", "Star", "Steel", "Stone", "Storm", "Summit", "Swift",
      "Tempest", "Thistle", "Thunder", "Timber", "Topaz", "Torch", "Trail", "Tundra",
      "Valiant", "Valley", "Vapor", "Vector", "Velvet", "Vertex", "Vesper", "Vortex",
      "Voyager", "Wave", "Whisper", "Willow", "Winter", "Wolf", "Zenith", "Zephyr"
    )

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

    fun generateLocal4WordPhrase(): String {
      val rng = SecureRandom()
      return (0 until 4).joinToString("-") {
        FALLBACK_WORDS[rng.nextInt(FALLBACK_WORDS.size)]
      }
    }

    fun generateLocal6DigitCode(): String {
      val rng = SecureRandom()
      val p1 = 100 + rng.nextInt(900)
      val p2 = 100 + rng.nextInt(900)
      return "%03d-%03d".format(p1, p2)
    }

    internal fun matchesLeadingHexZeros(digestBytes: ByteArray, hexZeros: Int): Boolean {
      val fullZeroBytes = hexZeros / 2
      for (i in 0 until fullZeroBytes) {
        if (digestBytes[i].toInt() != 0) return false
      }
      if (hexZeros % 2 == 1) {
        if ((digestBytes[fullZeroBytes].toInt() and 0xF0) != 0) return false
      }
      return true
    }
  }

  internal suspend fun solveArgon2idPuzzle(ip: String, time: Long): String = withContext(Dispatchers.Default) {
    require(!ip.contains(':') || ip.count { it == ':' } <= 7) { "Invalid IP format" }
    var nonce = 0L
    while (nonce < MAX_SOLVER_ITERATIONS) {
      coroutineContext.ensureActive()
      val secret = "$ip:$time:$nonce".toByteArray(Charsets.UTF_8)
      val hash = Argon2idPow.hash(secret, ARGON2_SALT)
      if (matchesLeadingHexZeros(hash, leadingHexZeros)) {
        return@withContext nonce.toString()
      }
      nonce++
    }
    throw IllegalStateException("Argon2id Proof-of-Work solver exceeded iteration budget")
  }

  private fun candidateBaseUrls(): List<String> {
    val configured = runCatching { appPrefs.zeroDirectoryUrl.get() }.getOrNull()
    return listOfNotNull(
      configured?.takeIf { it.isNotBlank() && it.startsWith("https://", ignoreCase = true) },
      directoryUrl
    ).map { it.trimEnd('/') }.distinct()
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
    localCryptoInviteUrl: String,
    dummyIp: String = "127.0.0.1"
  ): ZeroPhraseIdentity = withContext(Dispatchers.IO) {
    val cleanInvite = validateInviteUrl(localCryptoInviteUrl)
    val timestamp = System.currentTimeMillis() / 1000
    val verifiedNonce = solveArgon2idPuzzle(dummyIp, timestamp)

    val payload = buildJsonObject {
      put("invite_url", cleanInvite)
      put("nonce", verifiedNonce)
      put("timestamp", timestamp)
    }.toString()

    for (base in candidateBaseUrls()) {
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
      } catch (_: Throwable) {
      }
    }

    val fallbackPhrase = generateLocal4WordPhrase()
    val fallbackSlug = fallbackPhrase.lowercase().replace("-", "")
    cacheIdentityLocally(fallbackPhrase, cleanInvite)
    ZeroPhraseIdentity(
      phrase = fallbackPhrase,
      deepLink = "$DEEP_LINK_PREFIX$fallbackSlug",
      slug = fallbackSlug
    )
  }

  suspend fun provisionEphemeral6DigitCode(
    localCryptoInviteUrl: String,
    dummyIp: String = "127.0.0.1"
  ): ZeroEphemeralCode = withContext(Dispatchers.IO) {
    val cleanInvite = validateInviteUrl(localCryptoInviteUrl)
    val timestamp = System.currentTimeMillis() / 1000
    val verifiedNonce = solveArgon2idPuzzle(dummyIp, timestamp)

    val payload = buildJsonObject {
      put("invite_url", cleanInvite)
      put("nonce", verifiedNonce)
      put("timestamp", timestamp)
    }.toString()

    for (base in candidateBaseUrls()) {
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
      } catch (_: Throwable) {
      }
    }

    val fallbackCode = generateLocal6DigitCode()
    cacheIdentityLocally(fallbackCode, cleanInvite)
    ZeroEphemeralCode(fallbackCode, 300)
  }

  suspend fun resolveIdentity(rawTarget: String): String = withContext(Dispatchers.IO) {
    val target = extractResolveTarget(rawTarget)
    var lastError: Throwable? = null
    for (base in candidateBaseUrls()) {
      try {
        val responseText = executeHttpRequest(
          url = "$base/api/v1/identity/resolve/$target",
          method = "GET",
          body = null
        )
        val json = Json.parseToJsonElement(responseText).jsonObject
        val inviteUrl = json["invite_url"]?.jsonPrimitive?.content
        if (!inviteUrl.isNullOrBlank()) {
          validateInviteUrl(inviteUrl)
          return@withContext inviteUrl
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
      validateInviteUrl(cached)
      return@withContext cached
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

  private fun executeHttpRequest(url: String, method: String, body: String?): String {
    val proxy = resolveActiveSocksProxy()
    val conn = (if (proxy != null) URL(url).openConnection(proxy) else URL(url).openConnection()) as HttpURLConnection
    conn.connectTimeout = CONNECT_TIMEOUT_MS
    conn.readTimeout = READ_TIMEOUT_MS
    conn.requestMethod = method
    conn.setRequestProperty("User-Agent", MASKED_USER_AGENT)
    conn.setRequestProperty("Accept", "application/json")
    conn.setRequestProperty("Cache-Control", "no-store")
    if (body != null) {
      conn.doOutput = true
      conn.setRequestProperty("Content-Type", "application/json; charset=utf-8")
      OutputStreamWriter(conn.outputStream, Charsets.UTF_8).use { writer ->
        writer.write(body)
        writer.flush()
      }
    }
    val code = conn.responseCode
    val stream = if (code in 200..299) conn.inputStream else conn.errorStream
    val text = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() } ?: ""
    conn.disconnect()
    if (code !in 200..299) {
      throw IllegalStateException("Directory HTTP $code: $text")
    }
    return text
  }

  private fun resolveActiveSocksProxy(): Proxy? {
    return runCatching {
      val socksHostPort = appPrefs.networkSocksProxy.get()
      if (!socksHostPort.isNullOrBlank() && appPrefs.networkUseSocksProxy.get()) {
        val parts = socksHostPort.split(":")
        val host = parts[0].trim()
        val port = parts.getOrNull(1)?.trim()?.toIntOrNull() ?: 9050
        Proxy(Proxy.Type.SOCKS, InetSocketAddress(host, port))
      } else {
        null
      }
    }.getOrNull()
  }
}
