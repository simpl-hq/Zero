package app.zero.core.common.platform

import app.zero.core.common.zeroWindowState

actual fun allowedToShowNotification(): Boolean = !zeroWindowState.windowFocused.value
