package app.zero.core.common.views.chat.item

import android.Manifest
import android.os.Build
import androidx.compose.material.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.ui.platform.ClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp
import app.zero.core.common.model.ChatItem
import app.zero.core.common.model.MsgContent
import app.zero.core.common.platform.FileChooserLauncher
import app.zero.core.common.platform.saveImage
import app.zero.core.common.views.helpers.*
import app.zero.core.res.MR
import com.google.accompanist.permissions.PermissionStatus
import com.google.accompanist.permissions.rememberPermissionState
import dev.icerock.moko.resources.compose.painterResource
import dev.icerock.moko.resources.compose.stringResource

@Composable
actual fun ReactionIcon(text: String, fontSize: TextUnit) {
  Text(text, fontSize = fontSize)
}

@Composable
actual fun SaveContentItemAction(cItem: ChatItem, saveFileLauncher: FileChooserLauncher, showMenu: MutableState<Boolean>) {
  val writePermissionState = rememberPermissionState(permission = Manifest.permission.WRITE_EXTERNAL_STORAGE)
  ItemAction(stringResource(MR.strings.save_verb), painterResource(MR.images.ic_download), onClick = {
    when (cItem.content.msgContent) {
      is MsgContent.MCImage -> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R || writePermissionState.status == PermissionStatus.Granted) {
          saveImage(cItem.file)
        } else {
          writePermissionState.launchPermissionRequest()
        }
      }
      is MsgContent.MCFile, is MsgContent.MCVoice, is MsgContent.MCVideo -> withLongRunningApi { saveFileLauncher.launch(cItem.file?.fileName ?: "") }
      else -> {}
    }
    showMenu.value = false
  })
}

actual fun copyItemToClipboard(cItem: ChatItem, clipboard: ClipboardManager) {
  clipboard.setText(AnnotatedString(cItem.content.text))
}
