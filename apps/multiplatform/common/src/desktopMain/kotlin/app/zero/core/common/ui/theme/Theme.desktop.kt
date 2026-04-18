package app.zero.core.common.ui.theme

import androidx.compose.runtime.Composable
import app.zero.core.common.platform.Log
import app.zero.core.common.platform.TAG
import com.jthemedetecor.OsThemeDetector

private val detector: OsThemeDetector = OsThemeDetector.getDetector()
  .apply {
    registerListener(::reactOnDarkThemeChanges)
  }

@Composable
actual fun isSystemInDarkTheme(): Boolean = try {
  detector.isDark
}
catch (e: Exception) {
  Log.e(TAG, e.stackTraceToString())

  false
}
