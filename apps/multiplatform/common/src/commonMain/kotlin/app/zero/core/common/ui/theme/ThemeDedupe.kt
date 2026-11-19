package app.zero.core.common.ui.theme

import app.zero.core.common.views.helpers.WallpaperType

fun List<ThemeOverrides>.skipDuplicates(): List<ThemeOverrides> {
  val res = ArrayList<ThemeOverrides>()
  forEach { theme ->
    val themeType = WallpaperType.from(theme.wallpaper)
    if (res.none { it.themeId == theme.themeId || it.isSame(themeType, theme.base.themeName) }) {
      res.add(theme)
    }
  }
  return res
}
