package app.zero.core.common.views.call

import androidx.compose.desktop.ui.tooling.preview.Preview
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.painter.Painter
import dev.icerock.moko.resources.compose.painterResource
import dev.icerock.moko.resources.compose.stringResource
import androidx.compose.ui.unit.dp
import app.zero.core.common.model.*
import app.zero.core.common.platform.*
import app.zero.core.common.ui.theme.*
import app.zero.core.common.views.helpers.ProfileImage
import app.zero.core.common.views.usersettings.ProfilePreview
import app.zero.core.res.MR
import kotlinx.datetime.Clock

@Composable
fun IncomingCallAlertView(invitation: RcvCallInvitation, chatModel: ChatModel) {
  val cm = chatModel.callManager
  val scope = rememberCoroutineScope()
  LaunchedEffect(Unit) {
    if (chatModel.activeCallInvitation.value?.sentNotification == false || appPlatform.isDesktop) {
      SoundPlayer.start(scope, sound = !chatModel.showCallView.value)
    }
  }
  DisposableEffect(true) { onDispose { SoundPlayer.stop() } }
  IncomingCallAlertLayout(
    invitation,
    chatModel,
    rejectCall = { cm.endCall(invitation = invitation) },
    ignoreCall = {
      chatModel.activeCallInvitation.value = null
      ntfManager.cancelCallNotification()
    },
    acceptCall = {
      app.zero.core.common.views.helpers.AlertManager.shared.showAlertDialog(
        title = "Encrypted P2P call",
        text = "Calls and video calls are end-to-end encrypted, but connect peer-to-peer rather than through Tor and may temporarily expose your device's IP address.",
        confirmText = "Answer",
        onConfirm = { cm.acceptIncomingCall(invitation = invitation) }
      )
    }
  )
}

@Composable
fun IncomingCallAlertLayout(
  invitation: RcvCallInvitation,
  chatModel: ChatModel,
  rejectCall: () -> Unit,
  ignoreCall: () -> Unit,
  acceptCall: () -> Unit
) {
  val color = if (isInDarkTheme()) MaterialTheme.colors.surface else IncomingCallLight
  Column(Modifier.fillMaxWidth().background(color).statusBarsPadding().padding(top = DEFAULT_PADDING, bottom = DEFAULT_PADDING, start = DEFAULT_PADDING, end = 8.dp)) {
    IncomingCallInfo(invitation, chatModel)
    Spacer(Modifier.height(8.dp))
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
      Row(Modifier.fillMaxWidth().weight(1f), verticalAlignment = Alignment.CenterVertically) {
        ProfilePreview(profileOf = invitation.contact, size = 64.dp)
      }
      Row(verticalAlignment = Alignment.CenterVertically) {
        CallButton(stringResource(MR.strings.reject), painterResource(MR.images.ic_call_end_filled), Color.Red, rejectCall)
        CallButton(stringResource(MR.strings.ignore), painterResource(MR.images.ic_close), MaterialTheme.colors.primary, ignoreCall)
        CallButton(stringResource(MR.strings.accept), painterResource(MR.images.ic_check_filled), ZeroGreen, acceptCall)
      }
    }
  }
}

@Composable
fun IncomingCallInfo(invitation: RcvCallInvitation, chatModel: ChatModel) {
  @Composable fun CallIcon(icon: Painter, descr: String) = Icon(icon, descr, tint = ZeroGreen)
  Row(verticalAlignment = Alignment.CenterVertically) {
    if (chatModel.users.size > 1) {
      ProfileImage(size = 32.dp, image = invitation.user.profile.image, color = MaterialTheme.colors.secondaryVariant)
      Spacer(Modifier.width(4.dp))
    }
    if (invitation.callType.media == CallMediaType.Video) CallIcon(painterResource(MR.images.ic_videocam_filled), stringResource(MR.strings.icon_descr_video_call))
    else CallIcon(painterResource(MR.images.ic_call_filled), stringResource(MR.strings.icon_descr_audio_call))
    Spacer(Modifier.width(4.dp))
    Text(invitation.callTypeText, color = MaterialTheme.colors.onBackground)
  }
}

@Composable
private fun CallButton(text: String, icon: Painter, color: Color, action: () -> Unit) {
  Surface(
    shape = RoundedCornerShape(10.dp),
    color = Color.Transparent,
    contentColor = LocalContentColor.current
  ) {
    Column(
      Modifier
        .clickable(onClick = action)
        .defaultMinSize(minWidth = 50.dp)
        .padding(4.dp),
      horizontalAlignment = Alignment.CenterHorizontally
    ) {
      Icon(icon, text, tint = color, modifier = Modifier.scale(1.2f))
      Text(text, style = MaterialTheme.typography.body2, color = MaterialTheme.colors.secondary)
    }
  }
}

@Preview
@Composable
fun PreviewIncomingCallAlertLayout() {
  ZeroTheme {
    IncomingCallAlertLayout(
      invitation = RcvCallInvitation(
        remoteHostId = null,
        user = User.sampleData,
        contact = Contact.sampleData,
        callType = CallType(media = CallMediaType.Audio, capabilities = CallCapabilities(encryption = false)),
        sharedKey = null,
        callUUID = "",
        callTs = Clock.System.now()
      ),
      chatModel = ChatModel,
      rejectCall = {},
      ignoreCall = {},
      acceptCall = {}
    )
  }
}
