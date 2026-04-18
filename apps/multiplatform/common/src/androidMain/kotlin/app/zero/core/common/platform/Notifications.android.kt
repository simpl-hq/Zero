package app.zero.core.common.platform

actual fun allowedToShowNotification(): Boolean = !isAppOnForeground
