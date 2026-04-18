package app.zero.core.common.views.usersettings

import SectionView
import androidx.compose.runtime.Composable
import app.zero.core.common.model.ChatModel
import app.zero.core.res.MR
import dev.icerock.moko.resources.compose.stringResource

@Composable
actual fun PrivacyDeviceSection(
  showSettingsModal: (@Composable (ChatModel) -> Unit) -> (() -> Unit),
  setPerformLA: (Boolean) -> Unit,
) {
  SectionView(stringResource(MR.strings.settings_section_title_device)) {
    ChatLockItem(showSettingsModal, setPerformLA)
  }
}
