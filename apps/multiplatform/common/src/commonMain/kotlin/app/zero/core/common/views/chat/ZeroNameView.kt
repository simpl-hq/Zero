package app.zero.core.common.views.chat

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.*
import androidx.compose.ui.unit.dp
import dev.icerock.moko.resources.ImageResource
import app.zero.core.common.model.*
import app.zero.core.common.platform.*
import app.zero.core.common.ui.theme.DEFAULT_PADDING_HALF
import app.zero.core.common.views.helpers.*
import app.zero.core.res.MR
import dev.icerock.moko.resources.compose.painterResource
import dev.icerock.moko.resources.compose.stringResource
import kotlinx.coroutines.*

@Composable
fun ZeroNameView(
  zeroName: String,
  verified: Boolean?,
  verifiable: Boolean = true,
  verify: suspend () -> Pair<Boolean?, String?>?
) {
  val scope = rememberCoroutineScope()
  val inFlight = remember { mutableStateOf(false) }
  val showSpinner = remember { mutableStateOf(false) }

  fun runVerify(manual: Boolean) {
    if (inFlight.value) return
    inFlight.value = true
    scope.launch {
      val spinner = launch { delay(300); if (inFlight.value) showSpinner.value = true }
      val res = try {
        verify()
      } catch (e: Exception) {
        Log.e(TAG, "verify ZeroName: ${e.stackTraceToString()}")
        null
      }
      spinner.cancel()
      inFlight.value = false
      showSpinner.value = false
      if (res != null) {
        val (newV, reason) = res
        if (reason != null && (manual || newV == null)) {
          AlertManager.shared.showAlertMsg(generalGetString(MR.strings.zero_name_not_verified), reason)
        }
      }
    }
  }

  LaunchedEffect(Unit) {
    if (verifiable && chatModel.controller.appPrefs.privacyVerifyZeroNames.get() && verified == null) runVerify(manual = false)
  }

  val clipboard = LocalClipboardManager.current
  val nameStyle = MaterialTheme.typography.body2.copy(
    color = if (verified == true) MaterialTheme.colors.primary else MaterialTheme.colors.secondary
  )
  Row(
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(6.dp),
    modifier = Modifier.padding(top = DEFAULT_PADDING_HALF)
  ) {
    when {
      showSpinner.value -> {
        Text(zeroName, style = nameStyle)
        CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = MaterialTheme.colors.secondary)
      }
      verified == true ->
        ZeroNameWithIcon(zeroName, nameStyle, MR.images.ic_check_filled, MaterialTheme.colors.primary) {
          clipboard.setText(AnnotatedString(zeroName))
          showToast(generalGetString(MR.strings.copied))
        }
      !verifiable -> Text(zeroName, style = nameStyle)
      verified == false ->
        ZeroNameWithIcon(zeroName, nameStyle, MR.images.ic_close, Color.Red) { runVerify(manual = true) }
      else -> {
        Text(zeroName, style = nameStyle)
        Text(
          stringResource(MR.strings.verify_zero_name_action),
          color = MaterialTheme.colors.primary,
          modifier = Modifier.clickable { runVerify(manual = true) }
        )
      }
    }
  }
}

@Composable
private fun ZeroNameWithIcon(name: String, style: TextStyle, icon: ImageResource, tint: Color, onClick: () -> Unit) {
  Row(
    horizontalArrangement = Arrangement.spacedBy(2.dp),
    modifier = Modifier.clickable { onClick() }
  ) {
    Text(name, Modifier.alignByBaseline(), style = style)
    Icon(
      painterResource(icon), null,
      Modifier.size(22.dp).alignBy { it.measuredHeight * 73 / 100 },
      tint = tint
    )
  }
}

@Composable
fun ContactZeroNameView(contact: Contact, verifiable: Boolean = true) {
  val domain = contact.profile.contactDomain
  if (domain != null && (contact.profile.contactDomainVerified != null || domain.proof != null)) {
    ZeroNameView(
      zeroName = "@${domain.domain}",
      verified = contact.profile.contactDomainVerified,
      verifiable = verifiable,
      verify = {
        val rhId = chatModel.remoteHostId()
        chatModel.controller.apiVerifyContactDomain(rhId, contact.contactId)?.let { (ct, reason) ->
          chatModel.chatsContext.updateContact(rhId, ct)
          ct.profile.contactDomainVerified to reason
        }
      }
    )
  }
}

@Composable
fun GroupZeroNameView(groupInfo: GroupInfo, verifiable: Boolean = true) {
  if (groupInfo.businessChat == null) {
    val access = groupInfo.groupProfile.publicGroup?.publicGroupAccess
    val domain = access?.groupDomainClaim?.shortName
    if (domain != null && (groupInfo.groupDomainVerified != null || access.groupDomainClaim?.proof != null)) {
      ZeroNameView(
        zeroName = "#${domain}",
        verified = groupInfo.groupDomainVerified,
        verifiable = verifiable,
        verify = {
          val rhId = chatModel.remoteHostId()
          chatModel.controller.apiVerifyGroupDomain(rhId, groupInfo.groupId)?.let { (gInfo, reason) ->
            chatModel.chatsContext.updateGroup(rhId, gInfo)
            gInfo.groupDomainVerified to reason
          }
        }
      )
    }
  } else {
    val businessClaim = groupInfo.businessChat?.businessDomain
    if (businessClaim != null && (groupInfo.groupDomainVerified != null || businessClaim.proof != null)) {
      ZeroNameView(
        zeroName = "@${businessClaim.domain}",
        verified = groupInfo.groupDomainVerified,
        verifiable = false,
        verify = { null }
      )
    }
  }
}
