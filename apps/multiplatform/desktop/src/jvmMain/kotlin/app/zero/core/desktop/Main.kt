package app.zero.core.desktop

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.AnimationVector1D
import androidx.compose.foundation.*
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.runtime.*
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.*
import app.zero.core.common.acquireSingleInstance
import app.zero.core.common.model.ChatController.appPrefs
import app.zero.core.common.model.size
import app.zero.core.common.platform.*
import app.zero.core.common.platform.DesktopPlatform
import app.zero.core.common.showApp
import app.zero.core.common.views.helpers.*
import app.zero.core.common.views.onboarding.OnboardingStage
import kotlinx.coroutines.*
import java.io.File

fun main() {
  try {
    if (!acquireSingleInstance()) return
    preferencesTmpDir.deleteRecursively()
    initHaskell()
    runMigrations()
    setupUpdateChecker()
    initApp()
    tmpDir.deleteRecursively()
    tmpDir.mkdir()
    tmpDir.deleteOnExit()
    return showApp()
  } catch (e: Throwable) {
    showStartupError(e)
    throw e
  }
}

@OptIn(ExperimentalComposeUiApi::class)
@Suppress("UnsafeDynamicallyLoadedCode")
private fun initHaskell() {
  val resourcesDir = File(System.getProperty("compose.application.resources.dir"))
  val vlcDir = File(resourcesDir.absolutePath + File.separator + "vlc")
  if (desktopPlatform == DesktopPlatform.WINDOWS_X86_64) {
    windowsLoadRequiredLibs(resourcesDir, vlcDir)
  } else {
    System.load(File(resourcesDir, "libapp-lib.${desktopPlatform.libExtension}").absolutePath)
  }
  System.setProperty("jna.library.path", vlcDir.absolutePath)
  zero_core_runtime_init()

  platform = object: PlatformInterface {
    @Composable
    override fun desktopShowAppUpdateNotice() {
      fun showNoticeIfNeeded() {
        if (
          !chatModel.controller.appPrefs.appUpdateNoticeShown.get()
          && chatModel.controller.appPrefs.onboardingStage.get() == OnboardingStage.OnboardingComplete
          && chatModel.chats.size > 3
          && chatModel.activeCallInvitation.value == null
        ) {
          appPrefs.appUpdateNoticeShown.set(true)
          showAppUpdateNotice()
        }
      }
      LaunchedEffect(Unit) {
        showNoticeIfNeeded()
      }
      KeyChangeEffect(chatModel.chats.size) { oldSize ->
        if (oldSize == 0) {
          showNoticeIfNeeded()
        }
      }
    }
  }
}

private fun windowsLoadRequiredLibs(libsTmpDir: File, vlcDir: File) {
  val mainLibs = arrayOf(
    "libcrypto-3-x64.dll",
    "libzero.dll",
    "libapp-lib.dll"
  )
  mainLibs.forEach {
    System.load(File(libsTmpDir, it).absolutePath)
  }
  val vlcLibs = arrayOf(
    "libvlccore.dll",
    "libvlc.dll",
    "axvlc.dll",
    "npvlc.dll"
  )
  vlcLibs.forEach {
    System.load(File(vlcDir, it).absolutePath)
  }
}
