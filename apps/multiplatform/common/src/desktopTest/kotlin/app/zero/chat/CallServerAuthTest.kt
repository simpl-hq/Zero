package app.zero.chat

import app.zero.core.common.views.call.startServer
import java.net.Socket
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals

class CallServerAuthTest {
  private val token = "integration-test-token"
  private val server = startServer(onResponse = {}, port = 0, token = token)
  private val port get() = server.listeningPort

  @AfterTest
  fun tearDown() = server.stop()

  @Test
  fun testWebSocketUpgradeRejectedWithoutToken() {
    assertEquals(401, requestStatus(webSocketUpgrade(path = "/")))
  }

  @Test
  fun testWebSocketUpgradeRejectedWithWrongToken() {
    assertEquals(401, requestStatus(webSocketUpgrade(path = "/?token=wrong")))
  }

  @Test
  fun testWebSocketUpgradeAcceptedWithToken() {
    assertEquals(101, requestStatus(webSocketUpgrade(path = "/?token=$token")))
  }

  @Test
  fun testCallPageRejectedWithoutToken() {
    assertEquals(401, requestStatus(get(path = "/zero/call/")))
  }

  @Test
  fun testCallPagePassesAuthGateWithToken() {
    assertNotEquals(401, requestStatus(get(path = "/zero/call/?token=$token")))
  }

  private fun get(path: String): List<String> = listOf("GET $path HTTP/1.1", "Host: localhost:$port")

  private fun webSocketUpgrade(path: String): List<String> =
    listOf(
      "GET $path HTTP/1.1",
      "Host: localhost:$port",
      "Upgrade: websocket",
      "Connection: Upgrade",
      "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==",
      "Sec-WebSocket-Version: 13",
    )

  private fun requestStatus(requestLines: List<String>): Int =
    Socket("localhost", port).use { socket ->
      socket.soTimeout = 5000
      socket.getOutputStream().apply {
        write((requestLines.joinToString("\r\n") + "\r\n\r\n").toByteArray())
        flush()
      }
      val statusLine = socket.getInputStream().bufferedReader().readLine() ?: error("no response from call server")
      statusLine.split(" ")[1].toInt()
    }
}
