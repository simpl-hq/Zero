package app.zero.core.network

import kotlinx.coroutines.delay
import java.io.File

/**
 * Desktop (Windows/macOS/Linux) Tor launcher.
 * Looks for a `tor` binary in this order: bundled app resources (`<resources>/tor/`), then ZERO_TOR_BIN, then PATH.
 * Runs it with a private DataDirectory and SocksPort 9050, and stops it when the app exits.
 */
object TorDesktop {
  private var process: Process? = null
  @Volatile private var hookRegistered = false

  private fun exeName() = if (System.getProperty("os.name").lowercase().contains("win")) "tor.exe" else "tor"

  private fun findBinary(): File? {
    val name = exeName()
    val res = System.getProperty("compose.application.resources.dir")
    listOfNotNull(
      res?.let { File(it, "tor/$name") },
      System.getenv("ZERO_TOR_BIN")?.let { File(it) }
    ).firstOrNull { it.isFile }?.let { return it }
    val path = System.getenv("PATH") ?: return null
    return path.split(File.pathSeparator).map { File(it, name) }.firstOrNull { it.isFile }
  }

  fun register(dataRoot: File) {
    TorRuntime.starter = { start(dataRoot) }
  }

  private suspend fun start(dataRoot: File): Boolean {
    if (process?.isAlive == true) return true
    val bin = findBinary() ?: return false
    if (!System.getProperty("os.name").lowercase().contains("win")) {
      runCatching { bin.setExecutable(true) }
    }
    val dataDir = File(dataRoot, "tor-data").apply { mkdirs() }
    val pb = ProcessBuilder(
      bin.absolutePath,
      "--SocksPort", "${TorRuntime.SOCKS_HOST}:${TorRuntime.SOCKS_PORT}",
      "--DataDirectory", dataDir.absolutePath,
      "--ClientOnly", "1",
      "--AvoidDiskWrites", "1"
    ).redirectErrorStream(true).redirectOutput(ProcessBuilder.Redirect.DISCARD)
    bin.parentFile?.let { dir ->
      pb.directory(dir)
      val env = pb.environment()
      val os = System.getProperty("os.name").lowercase()
      if (os.contains("linux")) {
        val prev = env["LD_LIBRARY_PATH"]
        env["LD_LIBRARY_PATH"] = if (prev.isNullOrBlank()) dir.absolutePath else "${dir.absolutePath}:$prev"
      } else if (os.contains("mac")) {
        val prev = env["DYLD_LIBRARY_PATH"]
        env["DYLD_LIBRARY_PATH"] = if (prev.isNullOrBlank()) dir.absolutePath else "${dir.absolutePath}:$prev"
      }
    }
    process = pb.start()
    if (!hookRegistered) {
      hookRegistered = true
      Runtime.getRuntime().addShutdownHook(Thread { process?.destroy() })
    }
    repeat(200) {
      if (TorRuntime.isProxyUp()) return true
      if (process?.isAlive != true) return false
      delay(150)
    }
    return TorRuntime.isProxyUp()
  }
}
