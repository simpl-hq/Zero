package app.zero.core.common.views.call

import androidx.compose.runtime.Composable
import app.zero.core.common.model.*
import app.zero.core.common.model.ChatModel.controller
import app.zero.core.common.platform.*
import kotlinx.coroutines.*

@Composable
expect fun ActiveCallView()

fun activeCallWaitDeliveryReceipt(scope: CoroutineScope) = scope.launch(Dispatchers.Default) {
  for (msg in controller.messagesChannel) {
    val call = chatModel.activeCall.value
    if (call == null || call.callState > CallState.InvitationSent) break
    if (msg.rhId == call.remoteHostId &&
      msg is API.Result &&
      msg.res is CR.ChatItemsStatusesUpdated &&
      msg.res.chatItems.any {
        it.chatInfo.id == call.contact.id && it.chatItem.content is CIContent.SndCall && it.chatItem.meta.itemStatus is CIStatus.SndRcvd
      }
    ) {
      CallSoundsPlayer.startInCallSound(scope)
      break
    }
  }
}
