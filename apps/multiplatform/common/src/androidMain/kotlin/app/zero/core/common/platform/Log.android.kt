package app.zero.core.common.platform

import android.util.Log
import app.zero.core.common.model.ChatController.appPrefsOrNull

actual object Log {
  actual fun d(tag: String, text: String) { val p = appPrefsOrNull() ?: return; if (p.logLevel.get() <= LogLevel.DEBUG && p.developerTools.get()) Log.d(tag, text) }
  actual fun e(tag: String, text: String) { val p = appPrefsOrNull(); if (p == null || p.logLevel.get() <= LogLevel.ERROR || !p.developerTools.get()) Log.e(tag, text) }
  actual fun i(tag: String, text: String) { val p = appPrefsOrNull() ?: return; if (p.logLevel.get() <= LogLevel.INFO && p.developerTools.get()) Log.i(tag, text) }
  actual fun w(tag: String, text: String) { val p = appPrefsOrNull(); if (p == null || p.logLevel.get() <= LogLevel.WARNING || !p.developerTools.get()) Log.w(tag, text) }
}
