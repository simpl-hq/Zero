package app.zero.core.common.views.database

import androidx.compose.runtime.mutableStateOf
import app.zero.core.common.platform.chatModel
import app.zero.core.common.views.helpers.withBGApi
import kotlinx.coroutines.delay
import kotlinx.datetime.Instant

actual fun restartChatOrApp() {
  if (chatModel.chatRunning.value == false) {
    chatModel.chatDbChanged.value = true
    startChat(chatModel, mutableStateOf(Instant.DISTANT_PAST), chatModel.chatDbChanged, mutableStateOf(false))
  } else {
    authStopChat(chatModel) {
      withBGApi {
        delay(1000)
        chatModel.chatDbChanged.value = true
        startChat(chatModel, mutableStateOf(Instant.DISTANT_PAST), chatModel.chatDbChanged, mutableStateOf(false))
      }
    }
  }
}
