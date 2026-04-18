package app.zero.core.common

import androidx.compose.desktop.ui.tooling.preview.Preview
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.awt.ComposeWindow
import androidx.compose.ui.input.key.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.*
import app.zero.core.common.model.*
import app.zero.core.common.platform.*
import app.zero.core.common.ui.theme.DEFAULT_START_MODAL_WIDTH
import app.zero.core.common.ui.theme.ZeroTheme
import app.zero.core.common.views.TerminalView
import app.zero.core.common.views.helpers.*
import app.zero.core.res.MR
import dev.icerock.moko.resources.compose.painterResource
import dev.icerock.moko.resources.compose.stringResource
import kotlinx.coroutines.*
import java.awt.Frame
import java.awt.event.WindowEvent
import java.awt.event.WindowFocusListener
import java.io.File
import kotlin.system.exitProcess

val zeroWindowState = ZeroWindowState()

fun showApp() {
  trayIsAvailable
  while (true) {
    val closedByError = mutableStateOf(false)
    application(exitProcessOnExit = false) {
      CompositionLocalProvider(
        LocalWindowExceptionHandlerFactory provides WindowExceptionHandlerFactory { window ->
          WindowExceptionHandler { e ->
            AlertManager.shared.showAlertMsg(
              title = generalGetString(MR.strings.app_was_crashed),
              text = e.stackTraceToString(),
              shareText = true
            )
            Log.e(TAG, "App crashed, thread name: " + Thread.currentThread().name + ", exception: " + e.stackTraceToString())
            closedByError.value = true
            window.dispatchEvent(WindowEvent(window, WindowEvent.WINDOW_CLOSING))
            includeMoreFailedComposables()
            if (ModalManager.start.hasModalsOpen()) {
              ModalManager.start.closeModal()
            } else if (ModalManager.center.hasModalsOpen() || ModalManager.end.hasModalsOpen()) {
              ModalManager.center.closeModal()
              ModalManager.end.closeModal()
            } else {
              withApi {
                withContext(Dispatchers.Main) {
                  chatModel.chatId.value = null
                  chatModel.chatsContext.chatItems.clearAndNotify()
                }
                withContext(Dispatchers.Main) {
                  chatModel.secondaryChatsContext.value = null
                }
              }
            }
            chatModel.activeCall.value?.let {
              withBGApi {
                chatModel.callManager.endCall(it)
              }
            }
          }
        }
      ) {
        ZeroTray()
        AppWindow(closedByError)
      }
    }
    if (!closedByError.value) break
  }
  exitProcess(0)
}

@Composable
private fun ApplicationScope.AppWindow(closedByError: MutableState<Boolean>) {
  val state = getStoredWindowState()
  val windowState: WindowState = rememberWindowState(
    placement = WindowPlacement.Floating,
    width = state.width.dp,
    height = state.height.dp,
    position = WindowPosition(state.x.dp, state.y.dp)
  )

  val storingJob: MutableState<Job> = remember { mutableStateOf(Job()) }
  LaunchedEffect(
    windowState.position.x.value,
    windowState.position.y.value,
    windowState.size.width.value,
    windowState.size.height.value
  ) {
    storingJob.value.cancel()
    storingJob.value = launch {
      delay(1000L)
      storeWindowState(
        WindowPositionSize(
          x = windowState.position.x.value.toInt(),
          y = windowState.position.y.value.toInt(),
          width = windowState.size.width.value.toInt(),
          height = windowState.size.height.value.toInt()
        )
      )
    }
  }

  zeroWindowState.windowState = windowState
  if (remember { ChatController.appPrefs.appLanguage.state }.value != "") {
    Window(state = windowState, visible = zeroWindowState.windowVisible.value, icon = painterResource(MR.images.ic_zero), onCloseRequest = { handleCloseRequest(closedByError) }, onKeyEvent = {
      if (it.key == Key.Escape && it.type == KeyEventType.KeyUp) {
        zeroWindowState.backstack.lastOrNull()?.invoke() != null
      } else {
        false
      }
    }, title = "Zero") {
      zeroWindowState.window = window
      AppScreen()
      if (zeroWindowState.openDialog.isAwaiting) {
        FileDialogChooser(
          title = "Zero",
          isLoad = true,
          params = zeroWindowState.openDialog.params,
          onResult = {
            zeroWindowState.openDialog.onResult(it.firstOrNull())
          }
        )
      }

      if (zeroWindowState.openMultipleDialog.isAwaiting) {
        FileDialogChooser(
          title = "Zero",
          isLoad = true,
          params = zeroWindowState.openMultipleDialog.params,
          onResult = {
            zeroWindowState.openMultipleDialog.onResult(it)
          }
        )
      }

      if (zeroWindowState.saveDialog.isAwaiting) {
        FileDialogChooser(
          title = "Zero",
          isLoad = false,
          params = zeroWindowState.saveDialog.params,
          onResult = { zeroWindowState.saveDialog.onResult(it.firstOrNull()) }
        )
      }
      val toasts = remember { zeroWindowState.toasts }
      val toast = toasts.firstOrNull()
      if (toast != null) {
        ZeroTheme {
          Box(Modifier.fillMaxSize().padding(bottom = 20.dp), contentAlignment = Alignment.BottomCenter) {
            Text(
              escapedHtmlToAnnotatedString(toast.first, LocalDensity.current),
              Modifier.background(MaterialTheme.colors.primary, RoundedCornerShape(100)).padding(vertical = 5.dp, horizontal = 10.dp),
              color = MaterialTheme.colors.onPrimary,
              style = MaterialTheme.typography.body1
            )
          }
        }
        LaunchedEffect(toast, toasts.size) {
          delay(toast.second)
          zeroWindowState.toasts.removeFirstOrNull()
        }
      }
      var windowFocused by remember { zeroWindowState.windowFocused }
      LaunchedEffect(windowFocused) {
        val delay = ChatController.appPrefs.laLockDelay.get()
        if (!windowFocused && ChatModel.showAuthScreen.value && delay > 0) {
          delay(delay * 1000L)
          AppLock.recheckAuthState()
        }
      }
      LaunchedEffect(Unit) {
        window.addWindowFocusListener(object: WindowFocusListener {
          override fun windowGainedFocus(p0: WindowEvent?) {
            windowFocused = true
            AppLock.recheckAuthState()
          }

          override fun windowLostFocus(p0: WindowEvent?) {
            windowFocused = false
            AppLock.appWasHidden()
          }
        })
      }
    }
  }
  if (remember { ChatController.appPrefs.developerTools.state }.value && remember { ChatController.appPrefs.terminalAlwaysVisible.state }.value && remember { ChatController.appPrefs.appLanguage.state }.value != "") {
    var hiddenUntilRestart by remember { mutableStateOf(false) }
    if (!hiddenUntilRestart) {
      val cWindowState = rememberWindowState(placement = WindowPlacement.Floating, width = DEFAULT_START_MODAL_WIDTH * fontSizeSqrtMultiplier, height =
      768.dp)
      Window(state = cWindowState, onCloseRequest = { hiddenUntilRestart = true }, title = stringResource(MR.strings.chat_console)) {
        val data = remember { ModalData() }
        ZeroTheme {
          CompositionLocalProvider(LocalAppBarHandler provides data.appBarHandler) {
            ModalView({ hiddenUntilRestart = true }) {
              TerminalView(true)
            }
            ModalManager.floatingTerminal.showInView()
            DisposableEffect(Unit) {
              onDispose {
                ModalManager.floatingTerminal.closeModals()
              }
            }
          }
        }
      }
    }
  }
}

private fun ApplicationScope.handleCloseRequest(closedByError: MutableState<Boolean>) {
  if (closedByError.value) {
    exitApplication()
    return
  }
  val pref = ChatController.appPrefs.closeBehavior
  when (pref.get()) {
    CloseBehavior.Quit -> exitApplication()
    CloseBehavior.MinimizeToTray -> if (trayIsAvailable && singleInstanceLock) {
      zeroWindowState.windowVisible.value = false
    } else exitApplication()
    CloseBehavior.Ask -> if (trayIsAvailable && singleInstanceLock) {
      requestCloseBehavior()
    } else {
      pref.set(CloseBehavior.Quit)
      exitApplication()
    }
  }
}

fun showWindow() {
  zeroWindowState.windowVisible.value = true
  zeroWindowState.window?.apply {
    extendedState = extendedState and Frame.ICONIFIED.inv()
    toFront()
    requestFocus()
  }
}

class ZeroWindowState {
  lateinit var windowState: WindowState
  val backstack = mutableStateListOf<() -> Unit>()
  val openDialog = DialogState<File?>()
  val openMultipleDialog = DialogState<List<File>>()
  val saveDialog = DialogState<File?>()
  val toasts = mutableStateListOf<Pair<String, Long>>()
  var windowFocused = mutableStateOf(true)
  val windowVisible = mutableStateOf(true)
  var window: ComposeWindow? = null
}

data class DialogParams(
  val filename: String? = null,
  val allowMultiple: Boolean = false,
  val fileFilter: ((File?) -> Boolean)? = null,
  val fileFilterDescription: String = "",
)

class DialogState<T> {
  private var onResult: CompletableDeferred<T>? by mutableStateOf(null)
  var params = DialogParams()
  val isAwaiting get() = onResult != null

  suspend fun awaitResult(params: DialogParams = DialogParams()): T {
    onResult = CompletableDeferred()
    this.params = params
    val result = onResult!!.await()
    onResult = null
    return result
  }

  fun onResult(result: T) = onResult!!.complete(result)
}

@Preview
@Composable
fun AppPreview() {
  AppScreen()
}
