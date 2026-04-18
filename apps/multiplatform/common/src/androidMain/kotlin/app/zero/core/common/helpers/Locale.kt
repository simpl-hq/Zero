package app.zero.core.common.helpers

import android.app.Activity
import android.content.res.Configuration
import app.zero.core.common.model.SharedPreference
import app.zero.core.common.platform.androidAppContext
import app.zero.core.common.platform.defaultLocale
import java.util.*

fun Activity.saveAppLocale(pref: SharedPreference<String?>, languageCode: String? = null) {
  pref.set(languageCode)
  if (languageCode == null) {
    applyLocale(defaultLocale)
  }
  recreate()
}

fun Activity.applyAppLocale(pref: SharedPreference<String?>) {
  val lang = pref.get() ?: return
  applyLocale(Locale.forLanguageTag(lang))
}

private fun Activity.applyLocale(locale: Locale) {
  Locale.setDefault(locale)
  val appConf = Configuration(androidAppContext.resources.configuration).apply { setLocale(locale) }
  val activityConf = Configuration(resources.configuration).apply { setLocale(locale) }
  androidAppContext = androidAppContext.createConfigurationContext(appConf)
  @Suppress("DEPRECATION")
  resources.updateConfiguration(activityConf, resources.displayMetrics)
}
