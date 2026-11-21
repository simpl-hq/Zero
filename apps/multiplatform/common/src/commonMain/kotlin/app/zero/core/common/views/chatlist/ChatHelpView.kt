package app.zero.core.common.views.chatlist

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.*
import dev.icerock.moko.resources.compose.painterResource
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import dev.icerock.moko.resources.compose.stringResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.desktop.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.zero.core.common.ui.theme.*
import app.zero.core.common.views.helpers.annotatedStringResource
import app.zero.core.common.views.onboarding.ReadableTextWithLink
import app.zero.core.common.views.onboarding.openZeroGuidedTutorial
import app.zero.core.common.views.usersettings.MarkdownHelpView
import app.zero.core.res.MR

val bold = SpanStyle(fontWeight = FontWeight.Bold)

@Composable
fun ChatHelpView(addContact: (() -> Unit)? = null) {
  Column(
    verticalArrangement = Arrangement.spacedBy(10.dp)
  ) {
    Text(stringResource(MR.strings.thank_you_for_installing_zero), lineHeight = 22.sp)

    // quick guided walkthrough launcher card
    val ctaInk = MaterialTheme.colors.primary.onSurfaceInk()
    Surface(
      shape = RoundedCornerShape(16.dp),
      color = MaterialTheme.colors.primary,
      modifier = Modifier
        .fillMaxWidth()
        .padding(vertical = 4.dp)
        .clip(RoundedCornerShape(16.dp))
        .clickable { openZeroGuidedTutorial(allowSettingsShortcuts = true) }
    ) {
      Row(
        modifier = Modifier.padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically
      ) {
        Icon(
          painterResource(MR.images.ic_help),
          contentDescription = null,
          tint = ctaInk,
          modifier = Modifier.size(22.dp)
        )
        Column(
          modifier = Modifier.weight(1f),
          verticalArrangement = Arrangement.spacedBy(2.dp)
        ) {
          Text(
            "Open Guided Setup Tutorial",
            color = ctaInk,
            fontWeight = FontWeight.SemiBold,
            fontSize = 15.sp
          )
          Text(
            "4 interactive steps: phrase, pairing codes, onion routing & local lock",
            color = ctaInk.copy(alpha = 0.82f),
            fontSize = 12.sp
          )
        }
        Icon(
          painterResource(MR.images.ic_arrow_forward),
          contentDescription = null,
          tint = ctaInk.copy(alpha = 0.9f),
          modifier = Modifier.size(16.dp)
        )
      }
    }

    Column(
      Modifier.padding(top = 8.dp),
      verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
      Text("Quick overview", style = MaterialTheme.typography.h2, lineHeight = 22.sp)
      Text("4-Word Phrase: Zero uses no email or phone number. Share your 4-word phrase or simpl.global/add link when someone wants to reach you.", lineHeight = 20.sp)
      Text("6-Digit In-Person Code: Mint a 5-minute code from the guide or add-contact menu when pairing side by side or over a call.", lineHeight = 20.sp)
      Text("2-Hop Private Routing: Enable Private routing in Network & servers so your IP address never touches a contact's relay.", lineHeight = 20.sp)
      Text("Local Device Security: Messages stay encrypted only on your device with SQLCipher. Configure app lock in Privacy and back up your phrase.", lineHeight = 20.sp)
    }

    ReadableTextWithLink(MR.strings.you_can_connect_to_zero_core_runtime_founder, "https://github.com/simpl-hq/zero/issues", zeroLink = false)
    Column(
      Modifier.padding(top = 24.dp),
      verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
      Text(
        stringResource(MR.strings.to_start_a_new_chat_help_header),
        style = MaterialTheme.typography.h2,
        lineHeight = 22.sp
      )
      Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
      ) {
        Text(stringResource(MR.strings.chat_help_tap_button))
        Icon(
          painterResource(MR.images.ic_person_add),
          stringResource(MR.strings.add_contact),
          modifier = if (addContact != null) Modifier.clickable(onClick = addContact) else Modifier,
        )
        Text(stringResource(MR.strings.above_then_preposition_continuation))
      }
      Text(annotatedStringResource(MR.strings.add_contact_button_to_create_link_or_connect_via_link), lineHeight = 22.sp)
      Text(annotatedStringResource(MR.strings.create_group_button_to_create_new_group), lineHeight = 22.sp)
    }

    Column(
      Modifier.padding(top = 24.dp),
      verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
      Text(stringResource(MR.strings.to_connect_via_link_title), style = MaterialTheme.typography.h2)
      Text(stringResource(MR.strings.if_you_received_zero_invitation_link_you_can_open_in_browser), lineHeight = 22.sp)
      Text(annotatedStringResource(MR.strings.desktop_scan_QR_code_from_app_via_scan_QR_code), lineHeight = 22.sp)
      Text(annotatedStringResource(MR.strings.mobile_tap_open_in_mobile_app_then_tap_connect_in_app), lineHeight = 22.sp)
    }

    Column(
      Modifier.padding(vertical = 24.dp),
      verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
      Text(stringResource(MR.strings.markdown_in_messages), style = MaterialTheme.typography.h2)
      MarkdownHelpView()
    }
  }
}

@Preview

@Composable
fun PreviewChatHelpLayout() {
  ZeroTheme {
    ChatHelpView {}
  }
}
