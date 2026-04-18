package app.zero.chat

import app.zero.core.common.model.*
import app.zero.core.common.platform.chatModel
import app.zero.core.common.views.chat.providerForGallery
import kotlinx.datetime.Clock
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals

class ProviderForGalleryTest {

  @BeforeTest
  fun connectChatModelToRemote() {
    chatModel.currentRemoteHost.value = RemoteHostInfo(
      remoteHostId = 0L,
      hostDeviceName = "",
      storePath = "",
      bindAddress_ = null,
      bindPort_ = null,
      sessionState = null,
    )
  }

  @AfterTest
  fun resetChatModel() {
    chatModel.currentRemoteHost.value = null
  }

  @Test
  fun testScrollToStartPreservesAnchor() {
    val items = listOf(imageItem(1L), imageItem(2L), imageItem(3L))
    var scrolledTo: Int? = null
    val provider = providerForGallery(items, cItemId = 3L) { scrolledTo = it }

    provider.currentPageChanged(provider.initialIndex - 1)
    provider.scrollToStart()
    provider.onDismiss(0)

    assertEquals(1, scrolledTo)
  }

  @Test
  fun testOnDismissOnActiveItemDoesNotScroll() {
    val items = listOf(imageItem(1L), imageItem(2L), imageItem(3L))
    var scrolledTo: Int? = null
    val provider = providerForGallery(items, cItemId = 3L) { scrolledTo = it }

    provider.onDismiss(provider.initialIndex)

    assertEquals(null, scrolledTo)
  }

  private fun imageItem(id: Long): ChatItem =
    ChatItem(
      chatDir = CIDirection.DirectRcv(),
      meta = CIMeta.getSample(id, Clock.System.now(), text = ""),
      content = CIContent.RcvMsgContent(MsgContent.MCImage(text = "", image = "")),
      reactions = emptyList(),
      file = CIFile.getSample(fileId = id, fileName = "img-$id.jpg", filePath = "img-$id.jpg"),
    )
}
