package app.zero.core.common.platform

import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import app.zero.core.common.BuildConfigCommon
import app.zero.core.common.model.*
import app.zero.core.common.ui.theme.DefaultTheme
import app.zero.core.common.views.helpers.generalGetString
import app.zero.core.res.MR
import java.util.*

enum class AppPlatform {
  ANDROID, DESKTOP;

  val isAndroid: Boolean
    get() = this == ANDROID

  val isDesktop: Boolean
    get() = this == DESKTOP
}

expect val appPlatform: AppPlatform

expect val deviceName: String

expect fun isAppVisibleAndFocused(): Boolean

val appVersionInfo: Pair<String, Int?> = if (appPlatform == AppPlatform.ANDROID)
  BuildConfigCommon.ANDROID_VERSION_NAME to BuildConfigCommon.ANDROID_VERSION_CODE
else
  BuildConfigCommon.DESKTOP_VERSION_NAME to BuildConfigCommon.DESKTOP_VERSION_CODE

val databaseBackend: String = if (appPlatform == AppPlatform.ANDROID) "sqlite" else BuildConfigCommon.DATABASE_BACKEND

val androidPlayStoreCountry: MutableState<String?> = mutableStateOf(null)

class FifoQueue<E>(private var capacity: Int) : LinkedList<E>() {
  override fun add(element: E): Boolean {
    if (size > capacity) removeFirstOrNull()
    return super.add(element)
  }
}

fun runMigrations() {
  val lastMigration = ChatController.appPrefs.lastMigratedVersionCode
  if (lastMigration.get() < BuildConfigCommon.ANDROID_VERSION_CODE) {
    while (true) {
      if (lastMigration.get() < 117) {
        if (ChatController.appPrefs.currentTheme.get() == DefaultTheme.DARK.name) {
          ChatController.appPrefs.currentTheme.set(DefaultTheme.ZERO.name)
        }
        lastMigration.set(117)
      } else if (lastMigration.get() < 203) {
        val oldOverrides = ChatController.appPrefs.themeOverridesOld.get().values.toList()
        ChatController.appPrefs.themeOverrides.set(oldOverrides)
        ChatController.appPrefs.currentThemeIds.set(oldOverrides.associate { it.base.themeName to it.themeId })
        lastMigration.set(203)
      } else {
        lastMigration.set(BuildConfigCommon.ANDROID_VERSION_CODE)
        break
      }
    }
  }
}

enum class AppUpdatesChannel {
  DISABLED,
  STABLE,
  BETA;

  val text: String
    get() = when (this) {
      DISABLED -> generalGetString(MR.strings.app_check_for_updates_disabled)
      STABLE -> generalGetString(MR.strings.app_check_for_updates_stable)
      BETA -> generalGetString(MR.strings.app_check_for_updates_beta)
    }
}
