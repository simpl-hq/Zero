package app.zero.core.common.views

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.material.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import app.zero.core.common.ui.theme.isInDarkTheme
import app.zero.core.res.MR
import dev.icerock.moko.resources.compose.painterResource

@Composable
fun SplashView(nonTransparent: Boolean = false) {
  Surface(
    Modifier
      .fillMaxSize(),
    color = if (nonTransparent) MaterialTheme.colors.background.copy(1f) else MaterialTheme.colors.background,
    contentColor = LocalContentColor.current
  ) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
      Image(
        painterResource(if (isInDarkTheme()) MR.images.logo_light else MR.images.logo),
        contentDescription = "Zero",
        contentScale = ContentScale.Fit,
        modifier = Modifier.height(34.dp)
      )
    }
  }
}
