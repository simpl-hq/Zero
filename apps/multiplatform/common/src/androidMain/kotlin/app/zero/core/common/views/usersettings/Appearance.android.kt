package app.zero.core.common.views.usersettings

import SectionBottomSpacer
import SectionDividerSpaced
import SectionView
import android.app.Activity
import android.content.ComponentName
import android.content.pm.PackageManager
import android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_DEFAULT
import android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_ENABLED
import androidx.compose.desktop.ui.tooling.preview.Preview
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.MaterialTheme.colors
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import dev.icerock.moko.resources.compose.stringResource
import androidx.compose.ui.unit.dp
import app.zero.core.common.model.*
import app.zero.core.common.ui.theme.*
import app.zero.core.common.views.helpers.*
import app.zero.core.common.model.ChatModel
import app.zero.core.common.platform.*
import app.zero.core.common.helpers.APPLICATION_ID
import app.zero.core.common.helpers.saveAppLocale
import app.zero.core.common.model.ChatController.appPrefs
import app.zero.core.res.MR
import dev.icerock.moko.resources.ImageResource
import dev.icerock.moko.resources.compose.painterResource
import kotlinx.coroutines.delay

enum class AppIcon(val image: ImageResource) {
  DEFAULT(MR.images.ic_zero_light),
  DARK_BLUE(MR.images.ic_zero_dark),
}

@Composable
actual fun AppearanceView(m: ChatModel) {
  val appIcon = remember { mutableStateOf(findEnabledIcon()) }
  fun setAppIcon(newIcon: AppIcon) {
    if (appIcon.value == newIcon) return
    val newComponent = ComponentName(APPLICATION_ID, "app.zero.chat.MainActivity_${newIcon.name.lowercase()}")
    val oldComponent = ComponentName(APPLICATION_ID, "app.zero.chat.MainActivity_${appIcon.value.name.lowercase()}")
    androidAppContext.packageManager.setComponentEnabledSetting(
      newComponent,
      COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP
    )

    androidAppContext.packageManager.setComponentEnabledSetting(
      oldComponent,
      PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP
    )

    appIcon.value = newIcon
  }
  AppearanceScope.AppearanceLayout(
    appIcon,
    m.controller.appPrefs.appLanguage,
    m.controller.appPrefs.systemDarkTheme,
    changeIcon = ::setAppIcon,
  )
}

@Composable
fun AppearanceScope.AppearanceLayout(
  icon: MutableState<AppIcon>,
  languagePref: SharedPreference<String?>,
  systemDarkTheme: SharedPreference<String?>,
  changeIcon: (AppIcon) -> Unit,
) {
  ColumnWithScrollBar {
    AppBarTitle(stringResource(MR.strings.appearance_settings))
    SectionView(stringResource(MR.strings.settings_section_title_interface), contentPadding = PaddingValues()) {
      val context = LocalContext.current
      val state = rememberSaveable { mutableStateOf(languagePref.get() ?: "system") }
      LangSelector(state) {
        state.value = it
        withApi {
          delay(200)
          val activity = context as? Activity
          if (activity != null) {
            if (it == "system") {
              activity.saveAppLocale(languagePref)
            } else {
              activity.saveAppLocale(languagePref, it)
            }
          }
        }
      }

      SettingsPreferenceItem(icon = null, stringResource(MR.strings.one_hand_ui), ChatModel.controller.appPrefs.oneHandUI) { enabled ->
        if (enabled) appPrefs.chatBottomBar.set(true)
      }
      if (remember { appPrefs.oneHandUI.state }.value) {
        SettingsPreferenceItem(icon = null, stringResource(MR.strings.chat_bottom_bar), ChatModel.controller.appPrefs.chatBottomBar)
      }
    }

    SectionDividerSpaced()
    ThemesSection(systemDarkTheme)

    SectionDividerSpaced()
    AppToolbarsSection()

    SectionDividerSpaced()
    MessageShapeSection()

    SectionDividerSpaced()
    ProfileImageSection()

    SectionDividerSpaced()

    SectionView(stringResource(MR.strings.settings_section_title_icon), contentPadding = PaddingValues(horizontal = DEFAULT_PADDING_HALF, vertical = DEFAULT_PADDING_HALF)) {
      LazyRow {
        items(AppIcon.values().size, { index -> AppIcon.values()[index] }) { index ->
          val item = AppIcon.values()[index]
          Image(
            painterResource(item.image),
            contentDescription = "",
            contentScale = ContentScale.Fit,
            modifier = Modifier
              .border(1.dp, color = if (item == icon.value) colors.secondaryVariant else Color.Transparent, RoundedCornerShape(percent = 22))
              .clip(RoundedCornerShape(percent = 22))
              .size(70.dp)
              .clickable { changeIcon(item) }
              .padding(10.dp)
              .clip(CircleShape)
          )

          if (index + 1 != AppIcon.values().size) {
            Spacer(Modifier.padding(horizontal = 4.dp))
          }
        }
      }
    }

    SectionDividerSpaced()
    FontScaleSection()

    SectionBottomSpacer()
  }
}

private fun findEnabledIcon(): AppIcon = AppIcon.values().firstOrNull { icon ->
  androidAppContext.packageManager.getComponentEnabledSetting(
    ComponentName(APPLICATION_ID, "app.zero.chat.MainActivity_${icon.name.lowercase()}")
  ).let { it == COMPONENT_ENABLED_STATE_DEFAULT || it == COMPONENT_ENABLED_STATE_ENABLED }
} ?: AppIcon.DEFAULT

@Preview
@Composable
fun PreviewAppearanceSettings() {
  ZeroTheme {
    AppearanceScope.AppearanceLayout(
      icon = remember { mutableStateOf(AppIcon.DARK_BLUE) },
      languagePref = SharedPreference({ null }, {}),
      systemDarkTheme = SharedPreference({ null }, {}),
      changeIcon = {},
    )
  }
}
