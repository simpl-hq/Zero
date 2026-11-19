package app.zero.core.common.ui.theme

import androidx.compose.material.LocalContentColor
import androidx.compose.material.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.colorspace.ColorSpaces
import kotlin.math.cos
import kotlin.math.sin

fun oklch(L: Float, C: Float, H: Float, alpha: Float = 1f): Color {
  val hRad = H * (Math.PI.toFloat() / 180f)
  return Color(L, C * cos(hRad), C * sin(hRad), alpha, ColorSpaces.Oklab)
}

val Indigo = Color(0xFFA1A1A6)
val ZeroBlue = Color(0xFFE4E4E7)
val ZeroGreen = Color(77, 218, 103, 255)
val ZeroCanvasBlack = Color(0xFF000000)
val ZeroSurfaceDark = Color(0xFF0A0A0A)
val ZeroElevatedDark = Color(0xFF161617)
val ZeroBorderDark = Color(0xFF1F1F1F)
val ZeroBubbleBorderDark = Color(0xFF262626)
val ZeroTextSecondaryDark = Color(0xFF8E8E93)
val ZeroTextMuted = Color(0xFF52525B)
val ZeroQuoteDarkOnLight = Color(0xFFE4E4E7)
val ZeroQuoteDark = Color(0xFF222224)
val ZeroCanvasLight = Color(0xFFFFFFFF)
val ZeroSurfaceLight = Color(0xFFF5F5F7)
val ZeroElevatedLight = Color(0xFFF2F2F7)
val ZeroBorderLight = Color(0xFFE5E5EA)
val ZeroTextSecondaryLight = Color(0xFF6E6E73)
val ZeroQuoteLightOnDark = Color(0xFF1C1C1E)
val WarningRed = Color(0xFFEF4444)

val SecretColor = Color(0x40808080)
val LightGray = ZeroBorderLight
val DarkGray = ZeroElevatedDark
val HighOrLowlight = ZeroTextSecondaryDark
val MessagePreviewDark = Color(0xFFA1A1A6)
val MessagePreviewLight = Color(0xFF52525B)
val ToolbarLight = Color(0xF0FFFFFF)
val ToolbarDark = Color(0xE60A0A0A)
val SettingsSecondaryLight = Color(0xFFF2F2F7)
val GroupDark = Color(0xFF161617)
val IncomingCallLight = Color(0xFFF5F5F7)
val WarningOrange = Color(255, 127, 0, 255)
val WarningYellow = Color(255, 192, 0, 255)
val FileLight = ZeroTextSecondaryLight
val FileDark = Color(0xFF71717A)

fun Color.isLightSurface(): Boolean = luminance() > 0.45f
fun Color.onSurfaceInk(): Color = if (isLightSurface()) Color.Black else Color.White
fun Color.onSurfaceSecondaryInk(): Color = if (isLightSurface()) Color(0xFF52525B) else Color(0xFFA1A1A6)
fun Color.onSurfaceMutedInk(): Color = Color(0xFF71717A)

val MenuTextColor: Color @Composable get () = if (isInDarkTheme()) LocalContentColor.current.copy(alpha = 0.85f) else Color.Black
val NoteFolderIconColor: Color @Composable get() = MaterialTheme.colors.primary
