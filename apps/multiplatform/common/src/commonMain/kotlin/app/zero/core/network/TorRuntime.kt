package app.zero.core.network

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.InetSocketAddress
import java.net.Socket

/**
 * Platform-neutral hook for the embedded Tor client.
 * Each platform registers a [starter] that launches its bundled Tor and returns true once
 * a SOCKS5 listener is reachable on [SOCKS_HOST]:[SOCKS_PORT].
 * Zero never silently falls back to a direct connection: if Tor is not up, callers fail closed.
 */
object TorRuntime {
  const val SOCKS_HOST = "127.0.0.1"
  const val SOCKS_PORT = 9050

  @Volatile
  var starter: (suspend () -> Boolean)? = null

  fun isProxyUp(host: String = SOCKS_HOST, port: Int = SOCKS_PORT, timeoutMs: Int = 400): Boolean =
    runCatching { Socket().use { it.connect(InetSocketAddress(host, port), timeoutMs); true } }.getOrDefault(false)

  /** Starts the embedded Tor if needed. Returns true when a SOCKS proxy is reachable. */
  suspend fun ensureStarted(): Boolean = withContext(Dispatchers.IO) {
    if (isProxyUp()) return@withContext true
    val s = starter ?: return@withContext false
    runCatching { s() }.getOrDefault(false) && isProxyUp()
  }
}
