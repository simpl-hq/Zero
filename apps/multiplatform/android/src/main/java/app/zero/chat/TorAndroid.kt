package app.zero.chat

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.IBinder
import app.zero.core.common.platform.Log
import app.zero.core.network.TorRuntime
import kotlinx.coroutines.delay
import org.torproject.jni.TorService

object TorAndroid {
  private const val TAG = "TorAndroid"

  @Volatile
  private var serviceStarted = false

  private val connection = object : ServiceConnection {
    override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
      Log.d(TAG, "Bound to TorService")
    }

    override fun onServiceDisconnected(name: ComponentName?) {
      serviceStarted = false
      Log.d(TAG, "Disconnected from TorService")
    }
  }

  fun register(context: Context) {
    val appCtx = context.applicationContext
    TorRuntime.starter = { startAndWait(appCtx) }
  }

  fun startAsync(context: Context) {
    val appCtx = context.applicationContext
    runCatching {
      writeTorrc(appCtx)
      val intent = Intent(appCtx, TorService::class.java).apply {
        action = TorService.ACTION_START
      }
      appCtx.startService(intent)
      appCtx.bindService(Intent(appCtx, TorService::class.java), connection, Context.BIND_AUTO_CREATE)
      serviceStarted = true
    }.onFailure {
      Log.e(TAG, "Failed to start TorService: ${it.message}")
    }
  }

  private fun writeTorrc(context: Context) {
    val torrc = TorService.getTorrc(context)
    torrc.parentFile?.mkdirs()
    torrc.writeText(
      """
      SocksPort ${TorRuntime.SOCKS_HOST}:${TorRuntime.SOCKS_PORT}
      ClientOnly 1
      AvoidDiskWrites 1
      """.trimIndent() + "\n"
    )
  }

  private suspend fun startAndWait(context: Context): Boolean {
    if (TorRuntime.isProxyUp()) return true
    if (!serviceStarted) {
      startAsync(context)
    }
    repeat(200) {
      if (TorRuntime.isProxyUp()) return true
      delay(150)
    }
    return TorRuntime.isProxyUp()
  }
}
