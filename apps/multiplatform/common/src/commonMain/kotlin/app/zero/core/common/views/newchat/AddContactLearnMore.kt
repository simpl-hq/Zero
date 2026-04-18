package app.zero.core.common.views.newchat

import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import app.zero.core.common.platform.ColumnWithScrollBar
import app.zero.core.common.platform.chatModel
import app.zero.core.common.ui.theme.DEFAULT_PADDING
import dev.icerock.moko.resources.compose.stringResource
import app.zero.core.common.views.helpers.AppBarTitle
import app.zero.core.common.views.helpers.KeyChangeEffect
import app.zero.core.common.views.onboarding.ReadableText
import app.zero.core.common.views.onboarding.ReadableTextWithLink
import app.zero.core.res.MR

@Composable
fun AddContactLearnMore(close: () -> Unit) {
  ColumnWithScrollBar(Modifier.padding(horizontal = DEFAULT_PADDING)) {
    AppBarTitle(stringResource(MR.strings.one_time_link), withPadding = false)
    ReadableText(MR.strings.scan_qr_to_connect_to_contact)
    ReadableText(MR.strings.if_you_cant_meet_in_person)
    ReadableTextWithLink(MR.strings.read_more_in_user_guide_with_link, "https://github.com/simpl-hq/zero/blob/main/WHITEPAPER.md")
  }
  KeyChangeEffect(chatModel.chatId.value) {
    close()
  }
}
