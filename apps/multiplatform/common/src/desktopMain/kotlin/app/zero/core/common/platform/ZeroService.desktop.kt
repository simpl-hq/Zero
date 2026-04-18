package app.zero.core.common.platform

actual fun getWakeLock(timeout: Long): (() -> Unit) = {}
