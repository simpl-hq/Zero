package app.zero.core.common.views.usersettings

import SectionBottomSpacer
import SectionDividerSpaced
import SectionView
import itemHPadding
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import dev.icerock.moko.resources.compose.stringResource
import app.zero.core.common.BuildConfigCommon
import app.zero.core.common.model.ChatModel
import app.zero.core.common.model.CoreVersionInfo
import app.zero.core.common.platform.ColumnWithScrollBar
import app.zero.core.common.platform.appPlatform
import app.zero.core.common.platform.chatModel
import app.zero.core.common.ui.theme.DEFAULT_PADDING_HALF
import app.zero.core.common.views.helpers.AppBarTitle
import app.zero.core.res.MR

@Composable
fun VersionInfoView(
  showSettingsModal: (@Composable (ChatModel) -> Unit) -> (() -> Unit),
  withAuth: (title: String, desc: String, block: () -> Unit) -> Unit,
) {
  val versionInfo = remember { mutableStateOf<CoreVersionInfo?>(null) }
  LaunchedEffect(Unit) {
    versionInfo.value = chatModel.controller.apiGetVersion()
  }
  ColumnWithScrollBar {
    AppBarTitle(stringResource(MR.strings.app_version_title))
    SectionView {
      Column(Modifier.padding(horizontal = itemHPadding, vertical = DEFAULT_PADDING_HALF)) {
        if (appPlatform.isAndroid) {
          Text(String.format(stringResource(MR.strings.app_version_name), BuildConfigCommon.ANDROID_VERSION_NAME))
          Text(String.format(stringResource(MR.strings.app_version_code), BuildConfigCommon.ANDROID_VERSION_CODE))
        } else {
          Text(String.format(stringResource(MR.strings.app_version_name), BuildConfigCommon.DESKTOP_VERSION_NAME))
          Text(String.format(stringResource(MR.strings.app_version_code), BuildConfigCommon.DESKTOP_VERSION_CODE))
        }
        versionInfo.value?.let { info ->
          Text(String.format(stringResource(MR.strings.core_version), info.version))
          val isHexCommit = info.zeroqCommit.length >= 7 && info.zeroqCommit.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }
          val zeroqCommit = if (isHexCommit) info.zeroqCommit.substring(startIndex = 0, endIndex = 7) else info.zeroqCommit
          Text(String.format(stringResource(MR.strings.core_zeroq_version), info.zeroqVersion, zeroqCommit))
        }
      }
    }
    SectionDividerSpaced()

    AdvancedSettingsAppSection(showSettingsModal, withAuth)
    SectionBottomSpacer()
  }
}
