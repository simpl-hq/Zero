package app.zero.core.common

import app.zero.core.common.model.json
import app.zero.core.common.platform.appPreferences
import app.zero.core.common.platform.desktopPlatform
import app.zero.core.common.ui.theme.DEFAULT_WINDOW_WIDTH
import kotlinx.serialization.*

@Serializable
data class WindowPositionSize(
  val width: Int = DEFAULT_WINDOW_WIDTH.value.toInt(),
  val height: Int = 768,
  val x: Int = 0,
  val y: Int = 0,
)

fun getStoredWindowState(): WindowPositionSize =
  try {
    val str = appPreferences.desktopWindowState.get()
    var state = if (str == null) {
      WindowPositionSize()
    } else {
      json.decodeFromString(str)
    }

    if (desktopPlatform.isLinux() && state.width == 1366) {
      state = state.copy(width = 1376)
    }
    state
  } catch (e: Throwable) {
    WindowPositionSize()
  }

fun storeWindowState(state: WindowPositionSize) =
  appPreferences.desktopWindowState.set(json.encodeToString(state))
