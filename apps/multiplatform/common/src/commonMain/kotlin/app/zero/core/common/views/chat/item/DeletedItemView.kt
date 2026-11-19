package app.zero.core.common.views.chat.item

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.*
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.desktop.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.zero.core.common.model.ChatItem
import app.zero.core.common.ui.theme.*

@Composable
fun DeletedItemView(ci: ChatItem, timedMessagesTTL: Int?, showViaProxy: Boolean, showTimestamp: Boolean) {
  val sent = ci.chatDir.sent
  val bubbleBg = if (sent) MaterialTheme.appColors.sentMessage else MaterialTheme.appColors.receivedMessage
  val bubbleInk = bubbleBg.onSurfaceInk()
  val bubbleSecondaryInk = bubbleBg.onSurfaceSecondaryInk()
  Surface(
    shape = RoundedCornerShape(18.dp),
    color = bubbleBg,
    contentColor = bubbleInk
  ) {
    Row(
      Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
      verticalAlignment = Alignment.Bottom
    ) {
      Text(
        buildAnnotatedString {
          withStyle(SpanStyle(fontStyle = FontStyle.Italic, color = bubbleSecondaryInk)) { append(ci.content.text) }
        },
        style = MaterialTheme.typography.body1.copy(lineHeight = 22.sp),
        modifier = Modifier.padding(end = 8.dp)
      )
      CIMetaView(ci, timedMessagesTTL, metaColor = bubbleSecondaryInk, statusPrimaryColor = bubbleInk, showViaProxy = showViaProxy, showTimestamp = showTimestamp)
    }
  }
}

@Preview

@Composable
fun PreviewDeletedItemView() {
  ZeroTheme {
    DeletedItemView(
      ChatItem.getDeletedContentSampleData(),
      null,
      showViaProxy = false,
      showTimestamp = true
    )
  }
}
