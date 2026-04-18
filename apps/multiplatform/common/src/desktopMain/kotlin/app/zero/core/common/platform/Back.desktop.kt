package app.zero.core.common.platform

import androidx.compose.runtime.*
import app.zero.core.common.zeroWindowState

@Composable
actual fun BackHandler(enabled: Boolean, onBack: () -> Unit) {
  DisposableEffect(enabled) {
    if (enabled) zeroWindowState.backstack.add(onBack)
    onDispose {
      zeroWindowState.backstack.remove(onBack)
    }
  }
}
