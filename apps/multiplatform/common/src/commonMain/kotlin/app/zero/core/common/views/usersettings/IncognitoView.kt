package app.zero.core.common.views.usersettings

import SectionBottomSpacer
import androidx.compose.foundation.layout.*
import androidx.compose.material.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import dev.icerock.moko.resources.compose.stringResource
import androidx.compose.ui.unit.dp
import app.zero.core.common.platform.ColumnWithScrollBar
import app.zero.core.common.ui.theme.DEFAULT_PADDING
import app.zero.core.common.views.helpers.AppBarTitle
import app.zero.core.common.views.helpers.generalGetString
import app.zero.core.common.views.onboarding.ReadableTextWithLink
import app.zero.core.res.MR

@Composable
fun IncognitoView() {
  IncognitoLayout()
}

@Composable
fun IncognitoLayout() {
  ColumnWithScrollBar {
    AppBarTitle(stringResource(MR.strings.settings_section_title_incognito))
    Column(
      Modifier
        .padding(horizontal = DEFAULT_PADDING),
      verticalArrangement = Arrangement.spacedBy(20.dp)
    ) {
      Text(generalGetString(MR.strings.incognito_info_protects))
      Text(generalGetString(MR.strings.incognito_info_allows))
      Text(generalGetString(MR.strings.incognito_info_share))
      ReadableTextWithLink(MR.strings.read_more_in_user_guide_with_link, "https://github.com/simpl-hq/zero/blob/main/WHITEPAPER.md")
      SectionBottomSpacer()
    }
  }
}
