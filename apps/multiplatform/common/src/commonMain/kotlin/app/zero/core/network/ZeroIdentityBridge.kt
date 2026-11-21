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
import java.io.ByteArrayOutputStream
import java.io.EOFException
import java.io.InputStream
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URL
import java.security.MessageDigest
import java.security.cert.Certificate
import java.security.cert.X509Certificate
import java.util.Base64
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLPeerUnverifiedException
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory
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
    private val SIMPL_BROKER_HOSTS_SET = setOf(
      "zeroapi.simpl.global",
      "zeroeu.simpl.global",
      "zerona.simpl.global"
    )

    fun fromConfig(configured: String?): ZeroDiscoveryMode {
      val trimmed = configured?.trim()?.lowercase() ?: return SIMPL_NETWORK
      val clean = trimmed.trimEnd('/')
      return when {
        clean in setOf("air_gapped", "airgapped", "direct_only", "off", "disabled", "none", "") -> AIR_GAPPED
        clean in setOf("simpl_network", "default", "simpl") -> SIMPL_NETWORK
        clean.startsWith("https://") -> {
          val host = runCatching { URL(clean).host.lowercase() }.getOrNull()
          if (host != null && host in SIMPL_BROKER_HOSTS_SET) {
            SIMPL_NETWORK
          } else {
            SELF_HOSTED
          }
        }
        clean == "self_hosted" || clean == "custom" -> SELF_HOSTED
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
    // Verified CA SPKI SHA-256 pins (ISRG Root X2, Root YE, Let's Encrypt YE1/YE2, and current leaf) — survives 90-day leaf cert renewal while blocking rogue CAs.
    private val SIMPL_BROKER_SPKI_PINS = setOf(
      "YT1BaAU+tF7D8nnZSqBZCa+EB1XjRmCnTMv82dPAPno=",
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
    if (runCatching { appPrefs.networkUseSocksProxy.get() }.getOrDefault(false)) TorRuntime.ensureStarted()
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

    if (lastError != null && hasActiveProxy() && bases.isNotEmpty()) {
      throw IllegalStateException(
        "Tor protection is on, but no Tor proxy answered. Start Tor or Orbot (localhost:9050) and try again. " +
          "You can turn Tor off under Settings > Network & servers, but that exposes your IP address.",
        lastError
      )
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
    val httpsConn = conn as? HttpsURLConnection
      ?: throw SSLPeerUnverifiedException("Expected HTTPS connection for ${url.host}")
    verifyBrokerTlsCertificates(httpsConn.serverCertificates, url)
  }

  private fun verifyBrokerTlsCertificates(certs: Array<out Certificate>, url: URL) {
    if (!url.protocol.equals("https", ignoreCase = true)) {
      throw SSLPeerUnverifiedException("Plaintext HTTP rejected for broker host ${url.host}")
    }
    val host = url.host.lowercase()
    if (host !in SIMPL_BROKER_HOSTS) return
    val sha256 = MessageDigest.getInstance("SHA-256")
    val matched = certs.any { cert ->
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
    val proxyConfig = resolveActiveSocksProxy()
    if (proxyConfig != null) {
      return executeHttpOverSocks5h(parsedUrl, method, body, proxyConfig.first, proxyConfig.second)
    }
    val conn = parsedUrl.openConnection() as HttpURLConnection
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

  private fun executeHttpOverSocks5h(
    url: URL,
    method: String,
    body: String?,
    proxyHost: String,
    proxyPort: Int
  ): String {
    if (!url.protocol.equals("https", ignoreCase = true)) {
      throw SSLPeerUnverifiedException("Plaintext HTTP rejected for broker host ${url.host}")
    }
    val targetHost = url.host
    val targetPort = if (url.port > 0) url.port else 443
    val hostBytes = targetHost.toByteArray(Charsets.UTF_8)
    require(hostBytes.size in 1..255) { "Invalid host length for SOCKS5h: $targetHost" }

    val tunnel = Socket()
    try {
      tunnel.connect(InetSocketAddress(proxyHost, proxyPort), CONNECT_TIMEOUT_MS)
      tunnel.soTimeout = READ_TIMEOUT_MS
      val rawOut = tunnel.getOutputStream()
      val rawIn = tunnel.getInputStream()

      // SOCKS5 greeting: version 5, 1 auth method (no auth = 0x00)
      rawOut.write(byteArrayOf(0x05, 0x01, 0x00))
      rawOut.flush()
      val greet = readExactBytes(rawIn, 2)
      if (greet[0].toInt() != 0x05 || greet[1].toInt() != 0x00) {
        throw IllegalStateException("SOCKS5 handshake rejected (${greet[1].toInt() and 0xFF})")
      }

      // SOCKS5h CONNECT with ATYP=0x03 (domain name) so DNS resolves remotely inside Tor
      val req = ByteArrayOutputStream(7 + hostBytes.size)
      req.write(0x05)
      req.write(0x01) // CONNECT
      req.write(0x00) // RSV
      req.write(0x03) // DOMAINNAME
      req.write(hostBytes.size)
      req.write(hostBytes)
      req.write((targetPort ushr 8) and 0xFF)
      req.write(targetPort and 0xFF)
      rawOut.write(req.toByteArray())
      rawOut.flush()

      val respHead = readExactBytes(rawIn, 4)
      if (respHead[0].toInt() != 0x05 || respHead[1].toInt() != 0x00) {
        throw IllegalStateException("SOCKS5h connect failed with code ${respHead[1].toInt() and 0xFF}")
      }
      when (respHead[3].toInt() and 0xFF) {
        0x01 -> readExactBytes(rawIn, 4 + 2)
        0x03 -> {
          val len = rawIn.read()
          if (len < 0) throw EOFException("Unexpected EOF reading SOCKS5h bound domain")
          readExactBytes(rawIn, len + 2)
        }
        0x04 -> readExactBytes(rawIn, 16 + 2)
        else -> throw IllegalStateException("Unknown SOCKS5h address type: ${respHead[3].toInt() and 0xFF}")
      }

      val sslSocket = (SSLSocketFactory.getDefault() as SSLSocketFactory)
        .createSocket(tunnel, targetHost, targetPort, true) as SSLSocket
      sslSocket.soTimeout = READ_TIMEOUT_MS
      sslSocket.sslParameters = sslSocket.sslParameters.apply {
        endpointIdentificationAlgorithm = "HTTPS"
      }
      sslSocket.startHandshake()
      verifyBrokerTlsCertificates(sslSocket.session.peerCertificates, url)

      val pathWithQuery = buildString {
        append(url.path.ifEmpty { "/" })
        if (!url.query.isNullOrEmpty()) {
          append('?')
          append(url.query)
        }
      }
      val bodyBytes = body?.toByteArray(Charsets.UTF_8)
      val headerText = buildString {
        append("$method $pathWithQuery HTTP/1.1\r\n")
        append("Host: $targetHost\r\n")
        append("User-Agent: $MASKED_USER_AGENT\r\n")
        append("Accept: application/json\r\n")
        append("Cache-Control: no-store\r\n")
        append("Connection: close\r\n")
        if (bodyBytes != null) {
          append("Content-Type: application/json; charset=utf-8\r\n")
          append("Content-Length: ${bodyBytes.size}\r\n")
        }
        append("\r\n")
      }
      val tlsOut = sslSocket.outputStream
      tlsOut.write(headerText.toByteArray(Charsets.US_ASCII))
      if (bodyBytes != null) {
        tlsOut.write(bodyBytes)
      }
      tlsOut.flush()

      val tlsIn = sslSocket.inputStream
      val statusLine = readAsciiLine(tlsIn)
      val statusCode = statusLine.split(' ').getOrNull(1)?.toIntOrNull()
        ?: throw IllegalStateException("Malformed HTTP status line: $statusLine")
      val headers = mutableMapOf<String, String>()
      while (true) {
        val line = readAsciiLine(tlsIn)
        if (line.isEmpty()) break
        val idx = line.indexOf(':')
        if (idx > 0) {
          headers[line.substring(0, idx).trim().lowercase()] = line.substring(idx + 1).trim()
        }
      }

      val isChunked = headers["transfer-encoding"]?.lowercase()?.contains("chunked") == true
      val contentLength = headers["content-length"]?.toIntOrNull()
      val responseBytes = when {
        isChunked -> readChunkedBody(tlsIn)
        contentLength != null -> readExactBytes(tlsIn, contentLength)
        else -> tlsIn.readBytes()
      }
      val text = responseBytes.toString(Charsets.UTF_8)
      if (statusCode !in 200..299) {
        throw IllegalStateException("Directory HTTP $statusCode: $text")
      }
      return text
    } finally {
      runCatching { tunnel.close() }
    }
  }

  private fun readExactBytes(input: InputStream, count: Int): ByteArray {
    val buf = ByteArray(count)
    var offset = 0
    while (offset < count) {
      val n = input.read(buf, offset, count - offset)
      if (n < 0) throw EOFException("Unexpected EOF after $offset of $count bytes")
      offset += n
    }
    return buf
  }

  private fun readAsciiLine(input: InputStream): String {
    val out = ByteArrayOutputStream(64)
    while (true) {
      val b = input.read()
      if (b < 0) {
        if (out.size() == 0) throw EOFException("Unexpected EOF reading HTTP line")
        break
      }
      if (b == '\n'.code) break
      if (b != '\r'.code) out.write(b)
    }
    return out.toString(Charsets.US_ASCII.name())
  }

  private fun readChunkedBody(input: InputStream): ByteArray {
    val out = ByteArrayOutputStream()
    while (true) {
      val sizeLine = readAsciiLine(input).substringBefore(';').trim()
      val chunkSize = sizeLine.toIntOrNull(16)
        ?: throw IllegalStateException("Invalid HTTP chunk size: $sizeLine")
      if (chunkSize == 0) {
        while (readAsciiLine(input).isNotEmpty()) {}
        break
      }
      out.write(readExactBytes(input, chunkSize))
      readAsciiLine(input)
    }
    return out.toByteArray()
  }

  fun hasActiveProxy(): Boolean = resolveActiveSocksProxy() != null

  private fun resolveActiveSocksProxy(): Pair<String, Int>? {
    val useSocks = runCatching { appPrefs.networkUseSocksProxy.get() }.getOrDefault(false)
    if (!useSocks) return null
    val netProxy = try {
      appPrefs.networkProxy.get()
    } catch (t: Throwable) {
      throw IllegalStateException("Tor enabled but configuration could not be read", t)
    }
    val host = netProxy.host.trim().ifBlank { "127.0.0.1" }
    val port = netProxy.port
    if (port !in 1..65535) {
      throw IllegalStateException("Tor enabled with invalid port: $port")
    }
    return host to port
  }

  suspend fun relaySupportMessage(message: String, senderPin: String? = null): Boolean = withContext(Dispatchers.IO) {
    try {
      val bases = candidateBaseUrls().ifEmpty { listOf("https://zeroapi.simpl.global") }
      val payload = buildJsonObject {
        put("message", message)
        if (!senderPin.isNullOrBlank()) {
          put("sender_pin", senderPin)
        }
        put("client_version", "1.0.0")
        put("platform", "Desktop")
      }.toString()
      var sent = false
      for (base in bases) {
        try {
          executeHttpRequest("$base/api/v1/support/relay", "POST", payload)
          sent = true
          break
        } catch (_: Throwable) {}
      }
      sent
    } catch (_: Throwable) {
      false
    }
  }
}
