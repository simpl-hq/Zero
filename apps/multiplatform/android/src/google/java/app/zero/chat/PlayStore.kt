package app.zero.chat

import app.zero.core.common.platform.androidAppContext
import app.zero.core.common.platform.androidPlayStoreCountry
import com.android.billingclient.api.*

fun loadPlayStoreCountry() {
  val client = BillingClient.newBuilder(androidAppContext)
    .setListener { _, _ -> }
    .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
    .build()
  client.startConnection(object : BillingClientStateListener {
    override fun onBillingSetupFinished(result: BillingResult) {
      if (result.responseCode != BillingClient.BillingResponseCode.OK) {
        client.endConnection()
        return
      }
      client.getBillingConfigAsync(GetBillingConfigParams.newBuilder().build()) { configResult, config ->
        if (configResult.responseCode == BillingClient.BillingResponseCode.OK) {
          androidPlayStoreCountry.value = config?.countryCode
        }
        client.endConnection()
      }
    }

    override fun onBillingServiceDisconnected() = client.endConnection()
  })
}
