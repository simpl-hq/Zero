package app.zero.core.common.platform

expect fun getWakeLock(timeout: Long): (() -> Unit)
