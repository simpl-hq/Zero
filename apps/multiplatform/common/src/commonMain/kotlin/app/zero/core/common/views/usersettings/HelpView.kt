package app.zero.core.common.views.usersettings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import dev.icerock.moko.resources.compose.stringResource
import androidx.compose.desktop.ui.tooling.preview.Preview
import app.zero.core.common.platform.ColumnWithScrollBar
import app.zero.core.common.ui.theme.DEFAULT_PADDING
import app.zero.core.common.ui.theme.ZeroTheme
import app.zero.core.common.views.chatlist.ChatHelpView
import app.zero.core.common.views.helpers.AppBarTitle
import app.zero.core.res.MR

@Composable
fun HelpView(userDisplayName: String) {
  HelpLayout(userDisplayName)
}

@Composable
fun HelpLayout(userDisplayName: String) {
  ColumnWithScrollBar(Modifier.padding(horizontal = DEFAULT_PADDING)){
    AppBarTitle(String.format(stringResource(MR.strings.personal_welcome), userDisplayName), withPadding = false)
    ChatHelpView()
  }
}

@Preview

@Composable
fun PreviewHelpView() {
  ZeroTheme {
    HelpLayout("Alice")
  }
}
