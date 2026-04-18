package app.zero.core.common.views.usersettings.networkAndServers

import androidx.compose.runtime.Composable
import app.zero.core.common.model.UserServer

@Composable
actual fun ScanProtocolServer(rhId: Long?, onNext: (UserServer) -> Unit) {
  ScanProtocolServerLayout(rhId, onNext)
}
