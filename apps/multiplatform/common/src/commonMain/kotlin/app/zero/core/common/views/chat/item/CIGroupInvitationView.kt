package app.zero.core.common.views.chat.item

import androidx.compose.desktop.ui.tooling.preview.Preview
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.buildAnnotatedString
import dev.icerock.moko.resources.compose.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.zero.core.common.ui.theme.*
import app.zero.core.common.views.helpers.*
import app.zero.core.common.model.*
import app.zero.core.res.MR
import kotlinx.coroutines.delay

@Composable
fun CIGroupInvitationView(
  ci: ChatItem,
  groupInvitation: CIGroupInvitation,
  memberRole: GroupMemberRole,
  showTimestamp: Boolean,
  chatIncognito: Boolean = false,
  joinGroup: (Long, () -> Unit) -> Unit,
  timedMessagesTTL: Int?
) {
  val sent = ci.chatDir.sent
  val action = !sent && groupInvitation.status == CIGroupInvitationStatus.Pending
  val inProgress = remember { mutableStateOf(false) }
  var progressByTimeout by rememberSaveable { mutableStateOf(false) }
  LaunchedEffect(inProgress.value) {
    progressByTimeout = if (inProgress.value) {
      delay(1000)
      inProgress.value
    } else {
      false
    }
  }

  val sentColor = MaterialTheme.appColors.sentMessage
  val receivedColor = MaterialTheme.appColors.receivedMessage
  val bubbleBg = if (sent) sentColor else receivedColor
  val bubbleInk = bubbleBg.onSurfaceInk()
  val bubbleSecondaryInk = bubbleBg.onSurfaceSecondaryInk()

  @Composable
  fun groupInfoView() {
    val p = groupInvitation.groupProfile
    val iconColor =
      if (action && !inProgress.value) bubbleInk
      else bubbleSecondaryInk

    Row(
      Modifier.defaultMinSize(minWidth = 220.dp)
    ) {
      ProfileImage(size = 54.dp, image = groupInvitation.groupProfile.image, icon = MR.images.ic_supervised_user_circle_filled, color = iconColor)
      Spacer(Modifier.width(8.dp))
      Column(
        Modifier.defaultMinSize(minHeight = 54.dp),
        verticalArrangement = Arrangement.Center
      ) {
        Text(p.displayName, style = MaterialTheme.typography.caption, fontWeight = FontWeight.Medium, maxLines = 2, overflow = TextOverflow.Ellipsis)
        if (p.fullName != "" && p.displayName != p.fullName) {
          Text(p.fullName, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
      }
    }
  }

  @Composable
  fun groupInvitationStr(): String {
    return when {
      sent -> stringResource(MR.strings.you_sent_group_invitation)
      else -> when(groupInvitation.status) {
        CIGroupInvitationStatus.Pending -> stringResource(MR.strings.you_are_invited_to_group)
        CIGroupInvitationStatus.Accepted -> stringResource(MR.strings.you_joined_this_group)
        CIGroupInvitationStatus.Rejected -> stringResource(MR.strings.you_rejected_group_invitation)
        CIGroupInvitationStatus.Expired -> stringResource(MR.strings.group_invitation_expired)
      }
    }
  }

  Surface(
    modifier = if (action && !inProgress.value) Modifier.clickable(onClick = {
      inProgress.value = true
      joinGroup(groupInvitation.groupId) { inProgress.value = false }
    }) else Modifier,
    shape = RoundedCornerShape(18.dp),
    color = bubbleBg,
    contentColor = bubbleInk
  ) {
    Box(
      Modifier
        .width(IntrinsicSize.Min)
        .padding(start = 8.dp, end = 12.dp, top = 8.dp, bottom = 4.dp),
      contentAlignment = Alignment.BottomEnd
    ) {
      Box(
        contentAlignment = Alignment.Center
      ) {
        Column(
          Modifier
            .defaultMinSize(minWidth = 220.dp)
            .padding(bottom = 4.dp),
        ) {
          groupInfoView()
          val secondaryColor = bubbleSecondaryInk
          Divider(Modifier.fillMaxWidth().padding(top = 8.dp))
          Column(Modifier.padding(top = 8.dp, bottom = 4.dp, start = 4.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            if (action) {
              Text(groupInvitationStr(), fontSize = 13.sp, lineHeight = 18.sp)
              Text(
                buildAnnotatedString {
                  append(generalGetString(if (chatIncognito) MR.strings.group_invitation_tap_to_join_incognito else MR.strings.group_invitation_tap_to_join))
                  withStyle(reserveTimestampStyle) { append(reserveSpaceForMeta(ci.meta, timedMessagesTTL, encrypted = null, showStatus = false, showEdited = false, secondaryColor = secondaryColor, showTimestamp = showTimestamp)) }
                },
                fontWeight = FontWeight.Medium,
                color = if (inProgress.value) bubbleSecondaryInk else bubbleInk
              )
            } else {
              Text(
                buildAnnotatedString {
                  append(groupInvitationStr())
                  withStyle(reserveTimestampStyle) { append(reserveSpaceForMeta(ci.meta, timedMessagesTTL, encrypted = null, showStatus = false, showEdited = false, secondaryColor = secondaryColor, showTimestamp = showTimestamp)) }
                },
                fontSize = 13.sp,
                lineHeight = 18.sp,
              )
            }
          }
        }

        if (progressByTimeout) {
          CircularProgressIndicator(
            Modifier.size(32.dp),
            color = bubbleSecondaryInk,
            strokeWidth = 3.dp
          )
        }
      }

      CIMetaView(ci, timedMessagesTTL, metaColor = bubbleSecondaryInk, statusPrimaryColor = bubbleInk, showStatus = false, showEdited = false, showViaProxy = false, showTimestamp = showTimestamp)
    }
  }
}

@Preview

@Composable
fun PendingCIGroupInvitationViewPreview() {
  ZeroTheme {
    CIGroupInvitationView(
      ci = ChatItem.getGroupInvitationSample(),
      groupInvitation = CIGroupInvitation.getSample(),
      memberRole = GroupMemberRole.Admin,
      joinGroup = { _, _ -> },
      timedMessagesTTL = null,
      showTimestamp = true,
    )
  }
}

@Preview

@Composable
fun CIGroupInvitationViewAcceptedPreview() {
  ZeroTheme {
    CIGroupInvitationView(
      ci = ChatItem.getGroupInvitationSample(),
      groupInvitation = CIGroupInvitation.getSample(status = CIGroupInvitationStatus.Accepted),
      memberRole = GroupMemberRole.Admin,
      joinGroup = { _, _ -> },
      timedMessagesTTL = null,
      showTimestamp = true,
      )
  }
}

@Preview
@Composable
fun CIGroupInvitationViewLongNamePreview() {
  ZeroTheme {
    CIGroupInvitationView(
      ci = ChatItem.getGroupInvitationSample(),
      groupInvitation = CIGroupInvitation.getSample(
        groupProfile = GroupProfile("group_with_a_really_really_really_long_name", "Group With A Really Really Really Long Name", shortDescr = null),
        status = CIGroupInvitationStatus.Accepted
      ),
      memberRole = GroupMemberRole.Admin,
      joinGroup = { _, _ -> },
      timedMessagesTTL = null,
      showTimestamp = true,
      )
  }
}
