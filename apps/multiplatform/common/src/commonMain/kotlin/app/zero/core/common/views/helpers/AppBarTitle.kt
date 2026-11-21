package app.zero.core.common.views.helpers

import androidx.compose.foundation.layout.*
import androidx.compose.material.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.graphics.*
import androidx.compose.ui.unit.*
import app.zero.core.common.ui.theme.*
import app.zero.core.common.views.chatlist.*
import app.zero.core.res.MR
import dev.icerock.moko.resources.compose.painterResource
import kotlin.math.absoluteValue

@Composable
fun AppBarTitle(
  title: String,
  hostDevice: Pair<Long?, String>? = null,
  withPadding: Boolean = true,
  bottomPadding: Dp = DEFAULT_PADDING_HALF,
  enableAlphaChanges: Boolean = true,
  overrideTitleColor: Color? = null,
  textAlign: TextAlign = TextAlign.Center,
  lineHeight: TextUnit = TextUnit.Unspecified
) {
  val handler = LocalAppBarHandler.current
  LaunchedEffect(Unit) {
    handler?.title?.value = ""
    handler?.connection?.scrollTrackingEnabled = false
  }
  Spacer(Modifier.height(DEFAULT_PADDING_HALF))
}
