package app.zero.core.common

import app.zero.core.common.platform.Log
import app.zero.core.common.platform.TAG
import app.zero.core.common.platform.dataDir
import java.io.IOException
import java.nio.channels.FileChannel
import java.nio.channels.FileLock
import java.nio.channels.OverlappingFileLockException
import java.nio.file.*
import java.nio.file.StandardOpenOption.CREATE
import java.nio.file.StandardOpenOption.READ
import java.nio.file.StandardOpenOption.WRITE
import javax.swing.SwingUtilities
import kotlin.concurrent.thread

private var lockHandle: FileLock? = null
private var watcher: WatchService? = null

private val lockPath get() = dataDir.resolve("zero.started").toPath()
private val showPath get() = dataDir.resolve("zero.show").toPath()

var singleInstanceLock = false
  private set

private sealed interface LockResult {
  class Acquired(val lock: FileLock) : LockResult
  object Taken : LockResult
  object Failed : LockResult
}

fun acquireSingleInstance(): Boolean {
  dataDir.mkdirs()
  when (val result = tryAcquireLock()) {
    is LockResult.Acquired -> {
      lockHandle = result.lock
      singleInstanceLock = true
      deleteShowFile()
      startShowFileWatcher()
      return true
    }
    LockResult.Failed -> {
      return true
    }
    LockResult.Taken -> {
      createShowFile()
      val deadline = System.currentTimeMillis() + 1000
      while (Files.exists(showPath) && System.currentTimeMillis() < deadline) {
        try { Thread.sleep(50) } catch (_: InterruptedException) { break }
      }
      if (!Files.exists(showPath)) return false
      val start = showSingleInstanceAlert()
      if (start) deleteShowFile()
      return start
    }
  }
}

private fun tryAcquireLock(): LockResult {
  val channel = try {
    FileChannel.open(lockPath, READ, WRITE, CREATE)
  } catch (e: IOException) {
    Log.w(TAG, "single-instance: cannot open lock file: ${e.message}")
    return LockResult.Failed
  }
  return try {
    val lock = channel.tryLock(0L, 1L, false)
    if (lock != null) {
      LockResult.Acquired(lock)
    } else {
      channel.close()
      LockResult.Taken
    }
  } catch (_: OverlappingFileLockException) {
    Log.w(TAG, "single-instance: overlapping lock in same JVM")
    LockResult.Failed
  } catch (e: IOException) {
    Log.w(TAG, "single-instance: tryLock failed: ${e.message}")
    channel.close(); LockResult.Failed
  }
}

private fun deleteShowFile() {
  try { Files.deleteIfExists(showPath) } catch (e: IOException) {
    Log.w(TAG, "single-instance: cannot delete show file: ${e.message}")
  }
}

private fun createShowFile() {
  try { Files.createFile(showPath) } catch (_: FileAlreadyExistsException) {
  } catch (e: IOException) {
    Log.w(TAG, "single-instance: cannot create show file: ${e.message}")
  }
}

private fun showSingleInstanceAlert(): Boolean {
  val title = app.zero.core.common.views.helpers.generalGetString(app.zero.core.res.MR.strings.another_instance_title)
  val message = app.zero.core.common.views.helpers.generalGetString(app.zero.core.res.MR.strings.another_instance_not_responding)
  val result = javax.swing.JOptionPane.showConfirmDialog(
    null, message, title,
    javax.swing.JOptionPane.YES_NO_OPTION,
    javax.swing.JOptionPane.WARNING_MESSAGE
  )
  return result == javax.swing.JOptionPane.YES_OPTION
}

private fun startShowFileWatcher() {
  if (watcher != null) return
  val ws = try {
    dataDir.toPath().fileSystem.newWatchService()
  } catch (e: IOException) {
    Log.w(TAG, "single-instance: WatchService failed: ${e.message}")
    return
  }
  dataDir.toPath().register(ws, StandardWatchEventKinds.ENTRY_CREATE)
  watcher = ws
  thread(name = "zero-single-instance", isDaemon = true) {
    while (true) {
      val key = try { ws.take() } catch (_: ClosedWatchServiceException) { return@thread } catch (_: InterruptedException) { return@thread }
      for (event in key.pollEvents()) {
        if ((event.context() as? Path)?.fileName?.toString() == "zero.show") {
          deleteShowFile()
          SwingUtilities.invokeLater { showWindow() }
        }
      }
      if (!key.reset()) return@thread
    }
  }
}
