package app.zero.core.common.platform

import app.zero.core.common.model.ChatController.appPrefsOrNull

actual object Log {
  actual fun d(tag: String, text: String) { val p = appPrefsOrNull() ?: return; if (p.logLevel.get() <= LogLevel.DEBUG && p.developerTools.get()) println("D: $text") }
  actual fun e(tag: String, text: String) { val p = appPrefsOrNull(); if (p == null || p.logLevel.get() <= LogLevel.ERROR || !p.developerTools.get()) println("E: $text") }
  actual fun i(tag: String, text: String) { val p = appPrefsOrNull() ?: return; if (p.logLevel.get() <= LogLevel.INFO && p.developerTools.get()) println("I: $text") }
  actual fun w(tag: String, text: String) { val p = appPrefsOrNull(); if (p == null || p.logLevel.get() <= LogLevel.WARNING || !p.developerTools.get()) println("W: $text") }
}
