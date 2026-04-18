package app.zero.core.common.views.helpers

import app.zero.core.common.views.usersettings.LAMode

actual fun authenticate(
  promptTitle: String,
  promptSubtitle: String,
  selfDestruct: Boolean,
  usingLAMode: LAMode,
  oneTime: Boolean,
  completed: (LAResult) -> Unit
) {
  when (usingLAMode) {
    LAMode.PASSCODE -> authenticateWithPasscode(promptTitle, promptSubtitle, selfDestruct, oneTime, completed)
    else -> {}
  }
}
