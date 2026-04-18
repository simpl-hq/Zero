package app.zero.core.common.views.usersettings.networkAndServers

import androidx.compose.runtime.Composable
import dev.icerock.moko.resources.compose.stringResource
import app.zero.core.common.model.ServerAddress.Companion.parseServerAddress
import app.zero.core.common.model.UserServer
import app.zero.core.common.platform.ColumnWithScrollBar
import app.zero.core.common.views.helpers.*
import app.zero.core.common.views.newchat.QRCodeScanner
import app.zero.core.res.MR

@Composable
expect fun ScanProtocolServer(rhId: Long?, onNext: (UserServer) -> Unit)

@Composable
fun ScanProtocolServerLayout(rhId: Long?, onNext: (UserServer) -> Unit) {
  ColumnWithScrollBar {
    AppBarTitle(stringResource(MR.strings.smp_servers_scan_qr))
    QRCodeScanner { text ->
      val res = parseServerAddress(text)
      if (res != null) {
        onNext(UserServer(remoteHostId = rhId, null, text, false, null, false, false))
      } else {
        AlertManager.shared.showAlertMsg(
          title = generalGetString(MR.strings.smp_servers_invalid_address),
          text = generalGetString(MR.strings.smp_servers_check_address)
        )
      }
      res != null
    }
  }
}
