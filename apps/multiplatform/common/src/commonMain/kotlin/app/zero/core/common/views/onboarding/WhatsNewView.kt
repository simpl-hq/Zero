package app.zero.core.common.views.onboarding

import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.geometry.toRect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.PointerIcon
import androidx.compose.ui.input.pointer.pointerHoverIcon
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalUriHandler
import dev.icerock.moko.resources.compose.painterResource
import dev.icerock.moko.resources.compose.stringResource
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.desktop.ui.tooling.preview.Preview
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.zero.core.common.BuildConfigCommon
import app.zero.core.common.model.ChatController.appPrefs
import app.zero.core.common.model.ChatModel
import app.zero.core.common.model.*
import app.zero.core.common.model.ChatController.setConditionsNotified
import app.zero.core.common.model.ServerOperator.Companion.dummyOperatorInfo
import app.zero.core.common.platform.*
import app.zero.core.common.ui.theme.*
import app.zero.core.common.views.chat.item.CIFileViewScope
import app.zero.core.common.views.helpers.*
import app.zero.core.common.views.usersettings.UserAddressView
import app.zero.core.common.views.usersettings.networkAndServers.UsageConditionsView
import app.zero.core.common.views.usersettings.showAddShortLinkAlert
import app.zero.core.res.MR
import dev.icerock.moko.resources.ImageResource
import dev.icerock.moko.resources.StringResource
import kotlin.math.absoluteValue

@Composable
fun ModalData.WhatsNewView(updatedConditions: Boolean = false, viaSettings: Boolean = false, close: () -> Unit) {
  val currentVersion = remember { mutableStateOf(versionDescriptions.lastIndex) }
  val rhId = chatModel.remoteHostId()

  if (updatedConditions) {
    LaunchedEffect(Unit) {
      val conditionsId = chatModel.conditions.value.currentConditions.conditionsId
      try {
        setConditionsNotified(rh = rhId, conditionsId = conditionsId)
      } catch (e: Exception) {
        Log.d(TAG, "WhatsNewView setConditionsNotified error: ${e.message}")
      }
    }
  }

  @Composable
  fun featureDescription(icon: ImageResource?, titleId: StringResource, descrId: StringResource?, link: String?, subfeatures: List<Pair<ImageResource, StringResource>>) {
    @Composable
    fun linkButton(link: String) {
      val uriHandler = LocalUriHandler.current
      Icon(
        painterResource(MR.images.ic_open_in_new), stringResource(titleId), tint = MaterialTheme.colors.primary,
        modifier = Modifier
          .clickable { if (link.startsWith("zero:")) uriHandler.openVerifiedZeroUri(link) else uriHandler.openExternalLink(link) }
      )
    }

    Column(modifier = Modifier.padding(bottom = 12.dp)) {
      Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.padding(bottom = 4.dp)
      ) {
        if (icon != null)  Icon(painterResource(icon), stringResource(titleId), tint = MaterialTheme.colors.secondary)
        Text(
          generalGetString(titleId),
          maxLines = 2,
          overflow = TextOverflow.Ellipsis,
          style = MaterialTheme.typography.h4,
          fontWeight = FontWeight.Medium,
          modifier = Modifier.padding(bottom = 6.dp)
        )
        if (link != null) {
          linkButton(link)
        }
      }
      if (descrId != null) Text(generalGetString(descrId), fontSize = 15.sp)
      for ((si, sd) in subfeatures) {
        Row(
          verticalAlignment = Alignment.CenterVertically,
          horizontalArrangement = Arrangement.spacedBy(8.dp),
          modifier = Modifier.padding(bottom = 6.dp)
        ) {
          Icon(painterResource(si), stringResource(sd), tint = MaterialTheme.colors.secondary)
          Text(generalGetString(sd), fontSize = 15.sp)
        }
      }
    }
  }

  @Composable
  fun pagination() {
    Row(
      Modifier
        .padding(bottom = DEFAULT_PADDING)
    ) {
      if (currentVersion.value > 0) {
        val prev = currentVersion.value - 1
        Box(Modifier.clip(RoundedCornerShape(20.dp))) {
          Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier
              .clickable { currentVersion.value = prev }
              .padding(8.dp)
          ) {
            Icon(painterResource(MR.images.ic_arrow_back_ios_new), "previous", tint = MaterialTheme.colors.primary)
            Text(versionDescriptions[prev].version, color = MaterialTheme.colors.primary)
          }
        }
      }
      Spacer(Modifier.fillMaxWidth().weight(1f))
      if (currentVersion.value < versionDescriptions.lastIndex) {
        val next = currentVersion.value + 1
        Box(Modifier.clip(RoundedCornerShape(20.dp))) {
          Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier
              .clickable { currentVersion.value = next }
              .padding(8.dp)
          ) {
            Text(versionDescriptions[next].version, color = MaterialTheme.colors.primary)
            Icon(painterResource(MR.images.ic_arrow_forward_ios), "next", tint = MaterialTheme.colors.primary)
          }
        }
      }
    }
  }

  val v = versionDescriptions[currentVersion.value]

  ModalView(close = close) {
    ColumnWithScrollBar(
      Modifier
        .padding(horizontal = DEFAULT_PADDING),
      verticalArrangement = Arrangement.spacedBy(DEFAULT_PADDING.times(0.75f))
    ) {
      AppBarTitle(String.format(generalGetString(MR.strings.new_in_version), v.version), withPadding = false, bottomPadding = DEFAULT_PADDING)

      val modalManager = if (viaSettings) ModalManager.start else ModalManager.center

      v.features.forEach { feature ->
        when (feature) {
          is VersionFeature.FeatureDescription -> {
            if (feature.show) {
              featureDescription(feature.icon, feature.titleId, feature.descrId, feature.link, feature.subfeatures)
            }
          }
          is VersionFeature.FeatureView -> {
            feature.view(modalManager)
          }
        }
      }

      if (v.post != null) {
        ReadMoreButton(v.post)
      }

      if (updatedConditions) {
        Text(
          stringResource(MR.strings.view_updated_conditions),
          color = MaterialTheme.colors.primary,
          modifier = Modifier
            .clickable(
              interactionSource = remember { MutableInteractionSource() },
              indication = null
            ) {
              modalManager.showModalCloseable { close ->
                UsageConditionsView(
                  userServers = mutableStateOf(emptyList()),
                  currUserServers = mutableStateOf(emptyList()),
                  close = close,
                  rhId = rhId
                )
              }
            }
        )
      }

      if (!viaSettings) {
        Spacer(Modifier.fillMaxHeight().weight(1f))
        Box(
          Modifier.fillMaxWidth(), contentAlignment = Alignment.Center
        ) {
          Box(Modifier.clip(RoundedCornerShape(20.dp))) {
            Row(
              verticalAlignment = Alignment.CenterVertically,
              horizontalArrangement = Arrangement.Center,
              modifier = Modifier
                .clickable { close() }
                .padding(8.dp)
            ) {
              Text(
                generalGetString(MR.strings.ok),
                style = MaterialTheme.typography.h3,
                color = MaterialTheme.colors.primary
              )
            }
          }
        }
        Spacer(Modifier.fillMaxHeight().weight(1f))
      }

      Spacer(Modifier.fillMaxHeight().weight(1f))

      pagination()
    }
  }
}

@Composable
fun ReadMoreButton(url: String) {
  val uriHandler = LocalUriHandler.current
  Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = DEFAULT_PADDING.div(4))) {
    Text(
      stringResource(MR.strings.whats_new_read_more),
      color = MaterialTheme.colors.primary,
      modifier = Modifier
        .clickable(
          interactionSource = remember { MutableInteractionSource() },
          indication = null
        ) {
          uriHandler.openExternalLink(url)
        }
    )
    Icon(painterResource(MR.images.ic_open_in_new), stringResource(MR.strings.whats_new_read_more), tint = MaterialTheme.colors.primary)
  }
}

private sealed class VersionFeature {
  class FeatureDescription(
    val icon: ImageResource?,
    val titleId: StringResource,
    val descrId: StringResource?,
    var subfeatures: List<Pair<ImageResource, StringResource>> = listOf(),
    val link: String? = null,
    val show: Boolean = true
  ): VersionFeature()

  class FeatureView(
    val icon: ImageResource?,
    val titleId: StringResource,
    val view: @Composable (modalManager: ModalManager) -> Unit
  ): VersionFeature()
}

private data class VersionDescription(
  val version: String,
  val features: List<VersionFeature>,
  val post: String? = null,
)

private val versionDescriptions: List<VersionDescription> = listOf(
  VersionDescription(
    version = "v0.2",
    post = "https://github.com/simpl-hq/zero/blob/main/CHANGELOG.md",
    features = listOf(
      VersionFeature.FeatureDescription(
        icon = MR.images.ic_verified_user,
        titleId = MR.strings.v4_2_security_assessment,
        descrId = MR.strings.v4_2_security_assessment_desc,
        link = "https://github.com/simpl-hq/zero/blob/main/WHITEPAPER.md"
      ),
      VersionFeature.FeatureDescription(
        icon = MR.images.ic_check,
        titleId = MR.strings.v4_2_auto_accept_contact_requests,
        descrId = MR.strings.v4_2_auto_accept_contact_requests_desc
      ),
    )
  ),
  VersionDescription(
    version = "v0.3",
    post = "https://github.com/simpl-hq/zero/blob/main/CHANGELOG.md",
    features = listOf(
      VersionFeature.FeatureDescription(
        icon = MR.images.ic_group,
        titleId = MR.strings.v4_2_group_links,
        descrId = MR.strings.v4_2_group_links_desc
      ),
      VersionFeature.FeatureDescription(
        icon = MR.images.ic_mic,
        titleId = MR.strings.v4_3_voice_messages,
        descrId = MR.strings.v4_3_voice_messages_desc
      ),
      VersionFeature.FeatureDescription(
        icon = MR.images.ic_visibility_off,
        titleId = MR.strings.v4_3_improved_privacy_and_security,
        descrId = MR.strings.v4_3_improved_privacy_and_security_desc
      ),
    )
  ),
  VersionDescription(
    version = "v0.4",
    post = "https://github.com/simpl-hq/zero/blob/main/CHANGELOG.md",
    features = listOf(
      VersionFeature.FeatureDescription(
        icon = MR.images.ic_upload_file,
        titleId = MR.strings.v5_0_large_files_support,
        descrId = MR.strings.v5_0_large_files_support_descr
      ),
      VersionFeature.FeatureDescription(
        icon = MR.images.ic_timer,
        titleId = MR.strings.v4_4_disappearing_messages,
        descrId = MR.strings.v4_4_disappearing_messages_desc
      ),
      VersionFeature.FeatureDescription(
        icon = MR.images.ic_desktop,
        titleId = MR.strings.v5_4_link_mobile_desktop,
        descrId = MR.strings.v5_4_link_mobile_desktop_descr
      ),
    )
  ),
  VersionDescription(
    version = "v0.5",
    post = "https://github.com/simpl-hq/zero/blob/main/CHANGELOG.md",
    features = listOf(
      VersionFeature.FeatureDescription(
        icon = MR.images.ic_vpn_key_filled,
        titleId = MR.strings.v6_1_better_security,
        descrId = MR.strings.v6_1_better_security_descr,
        link = "https://github.com/simpl-hq/zero/blob/main/WHITEPAPER.md"
      ),
      VersionFeature.FeatureDescription(
        icon = MR.images.ic_settings_ethernet,
        titleId = MR.strings.v5_8_private_routing,
        descrId = MR.strings.v5_8_private_routing_descr
      ),
      VersionFeature.FeatureDescription(
        icon = MR.images.ic_wifi_tethering,
        titleId = MR.strings.v5_7_network,
        descrId = MR.strings.v5_7_network_descr
      ),
    )
  ),
  VersionDescription(
    version = "v0.6",
    post = "https://github.com/simpl-hq/zero/blob/main/CHANGELOG.md",
    features = listOf(
      VersionFeature.FeatureDescription(
        icon = MR.images.ic_call,
        titleId = MR.strings.v4_6_audio_video_calls,
        descrId = MR.strings.v4_6_audio_video_calls_descr
      ),
      VersionFeature.FeatureDescription(
        icon = MR.images.ic_ios_share,
        titleId = MR.strings.v5_6_app_data_migration,
        descrId = MR.strings.v5_6_app_data_migration_descr
      ),
      VersionFeature.FeatureDescription(
        icon = MR.images.ic_lock,
        titleId = MR.strings.v5_3_encrypt_local_files,
        descrId = MR.strings.v5_3_encrypt_local_files_descr
      ),
    )
  ),
  VersionDescription(
    version = "v0.7",
    post = "https://github.com/simpl-hq/zero/blob/main/CHANGELOG.md",
    features = listOf(
      VersionFeature.FeatureDescription(
        icon = MR.images.ic_manage_accounts,
        titleId = MR.strings.v4_5_multiple_chat_profiles,
        descrId = MR.strings.v4_5_multiple_chat_profiles_descr
      ),
      VersionFeature.FeatureDescription(
        icon = MR.images.ic_lock,
        titleId = MR.strings.v4_6_hidden_chat_profiles,
        descrId = MR.strings.v4_6_hidden_chat_profiles_descr
      ),
      VersionFeature.FeatureDescription(
        icon = MR.images.ic_chat_person,
        titleId = MR.strings.v6_4_review_members,
        descrId = MR.strings.v6_4_review_members_descr
      ),
      VersionFeature.FeatureDescription(
        icon = MR.images.ic_at,
        titleId = MR.strings.v6_3_mentions,
        descrId = MR.strings.v6_3_mentions_descr
      ),
    )
  ),
  VersionDescription(
    version = "v0.8",
    post = "https://github.com/simpl-hq/zero/blob/main/CHANGELOG.md",
    features = listOf(
      VersionFeature.FeatureDescription(
        icon = MR.images.ic_menu,
        titleId = MR.strings.v6_3_organize_chat_lists,
        descrId = MR.strings.v6_3_organize_chat_lists_descr
      ),
      VersionFeature.FeatureDescription(
        icon = MR.images.ic_security,
        titleId = MR.strings.v6_5_safe_web_links,
        descrId = MR.strings.v6_5_safe_web_links_descr
      ),
      VersionFeature.FeatureDescription(
        icon = null,
        titleId = MR.strings.v6_1_better_user_experience,
        descrId = null,
        subfeatures = listOf(
          MR.images.ic_link to MR.strings.v6_1_switch_chat_profile_descr,
          MR.images.ic_forward to MR.strings.v6_1_forward_many_messages_descr,
          MR.images.ic_delete to MR.strings.v6_1_delete_many_messages_descr
        )
      ),
    )
  ),
  VersionDescription(
    version = "v0.9",
    post = "https://github.com/simpl-hq/zero/blob/main/CHANGELOG.md",
    features = listOf(
      VersionFeature.FeatureDescription(
        icon = null,
        titleId = MR.strings.v6_5_public_channels,
        descrId = null,
        subfeatures = listOf(
          MR.images.ic_wifi_tethering to MR.strings.v6_5_reliability,
          MR.images.ic_dns to MR.strings.v6_5_ownership,
          MR.images.ic_vpn_key_filled to MR.strings.v6_5_security,
          MR.images.ic_shield to MR.strings.v6_5_privacy,
        )
      ),
      VersionFeature.FeatureDescription(
        icon = null,
        titleId = MR.strings.v7_0_channels,
        descrId = null,
        subfeatures = listOf(
          MR.images.ic_person_add to MR.strings.v7_0_channels_contributors,
          MR.images.ic_travel_explore to MR.strings.v7_0_channels_previews,
          MR.images.ic_dns to MR.strings.v7_0_channels_relays,
          MR.images.ic_article to MR.strings.v7_0_channels_wider_messages,
        )
      ),
    )
  ),
  VersionDescription(
    version = "v1.0.0",
    post = "https://github.com/simpl-hq/zero/blob/main/CHANGELOG.md",
    features = listOf(
      VersionFeature.FeatureDescription(
        icon = MR.images.ic_alternate_email,
        titleId = MR.strings.v7_0_zero_names,
        descrId = MR.strings.v7_0_zero_names_descr
      ),
      VersionFeature.FeatureView(
        icon = null,
        titleId = MR.strings.v6_4_1_short_address,
        view = { modalManager -> CreateUpdateAddressShortLinkView(modalManager) }
      ),
      VersionFeature.FeatureDescription(
        icon = MR.images.ic_wifi_tethering,
        titleId = MR.strings.v6_0_connection_servers_status,
        descrId = MR.strings.v6_0_connection_servers_status_descr
      ),
      VersionFeature.FeatureDescription(
        icon = MR.images.ic_verified_user,
        titleId = MR.strings.v6_5_non_profit_governance,
        descrId = MR.strings.v6_5_non_profit_governance_descr
      ),
      VersionFeature.FeatureDescription(
        icon = MR.images.ic_upgrade,
        titleId = MR.strings.v6_0_upgrade_app,
        descrId = MR.strings.v6_0_upgrade_app_descr,
        show = appPlatform.isDesktop
      ),
    )
  ),
)

private val lastVersion = versionDescriptions.last().version

fun setLastVersionDefault(m: ChatModel) {
  if (appPrefs.whatsNewVersion.get() != lastVersion) {
    appPrefs.whatsNewVersion.set(lastVersion)
  }
}

fun shouldShowWhatsNew(m: ChatModel): Boolean {
  val v = m.controller.appPrefs.whatsNewVersion.get()
  setLastVersionDefault(m)
  return v != lastVersion
}

private const val DONATE_URL = "https://simpl.global/donate"

private const val SUPPORT_CONTACT_URI = "https://simpl.global/donate"

private val MAX_CROWDFUNDING_IMAGE_WIDTH = DEFAULT_MIN_CENTER_MODAL_WIDTH

private val CROWDFUNDING_PAGE_IMAGE_WIDTH = DEFAULT_MIN_CENTER_MODAL_WIDTH

private val CROWDFUNDING_IMAGE_CORNER_RADIUS = 12.dp
private const val CROWDFUNDING_IMAGE_CORNER_RADIUS_RATIO = 0.03f

private class CrowdfundingLayout(
  val maxImageWidth: Dp,
  val imageShape: Shape,
  private val centerOfWindow: ModalManager?
) {
  fun inCenterOfWindow(modalManager: ModalManager) = modalManager === centerOfWindow
}

private val crowdfundingLayout = if (appPlatform.isDesktop)
  CrowdfundingLayout(CROWDFUNDING_PAGE_IMAGE_WIDTH, object : Shape {
    override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density): Outline =
      Outline.Rounded(RoundRect(size.toRect(), CornerRadius(size.width * CROWDFUNDING_IMAGE_CORNER_RADIUS_RATIO)))
  }, ModalManager.center)
else
  CrowdfundingLayout(Dp.Unspecified, RoundedCornerShape(CROWDFUNDING_IMAGE_CORNER_RADIUS), null)

@Composable
fun crowdfundingAvailable(): Boolean = false

fun isInUs(): Boolean = false

@Composable
private fun InvestInZeroView(modalManager: ModalManager) {
  if (!crowdfundingAvailable()) return
  val showGetStake = { modalManager.showModalCloseable(cardScreen = true) { close -> GetStakeView(showFirstImage = false, inCenterOfWindow = crowdfundingLayout.inCenterOfWindow(modalManager), close = close) } }
  Column(modifier = Modifier.padding(bottom = 12.dp)) {
    Text(
      generalGetString(MR.strings.v7_0_invest),
      style = MaterialTheme.typography.h4,
      fontWeight = FontWeight.Medium,
      modifier = Modifier.padding(bottom = 6.dp)
    )
    Text(
      buildAnnotatedString {
        append(generalGetString(MR.strings.v7_0_invest_descr))
        append(" ")
        withStyle(SpanStyle(color = MaterialTheme.colors.primary)) {
          append(generalGetString(MR.strings.learn_more))
        }
      },
      fontSize = 15.sp,
      modifier = Modifier
        .pointerHoverIcon(PointerIcon.Hand)
        .clickable(
          interactionSource = remember { MutableInteractionSource() },
          indication = null,
          onClick = showGetStake
        )
    )
    if (BuildConfigCommon.ZERO_ASSETS) {
      Image(
        painterResource(MR.images.crowdfunding_1),
        contentDescription = null,
        contentScale = ContentScale.FillWidth,
        modifier = Modifier
          .padding(top = 8.dp)
          .widthIn(max = MAX_CROWDFUNDING_IMAGE_WIDTH)
          .fillMaxWidth()
          .clip(crowdfundingLayout.imageShape)
          .pointerHoverIcon(PointerIcon.Hand)
          .clickable(
            interactionSource = remember { MutableInteractionSource() },
            indication = null,
            onClick = showGetStake
          )
      )
    }
  }
}

private class CrowdfundingSlide(
  val image: ImageResource,
  val heading: String,
  val info: String?,
  val text: String,
)

private val getStakeSlides: List<CrowdfundingSlide> = listOf(
  CrowdfundingSlide(
    MR.images.crowdfunding_1,
    "Zero-identifier private messaging",
    null,
    "Zero removes phone numbers, usernames, and server-side social graphs so communication stays private by math rather than policy."
  ),
  CrowdfundingSlide(
    MR.images.crowdfunding_2,
    "Post-quantum and open source",
    null,
    "Every component—from Curve448 + sntrup761 transport to the Argon2id contact-code broker—is auditable under AGPL-3.0."
  ),
  CrowdfundingSlide(
    MR.images.crowdfunding_3,
    "Independent relay infrastructure",
    "Relays store no user accounts and retain no plaintext history.",
    "Community donations directly cover relay bandwidth, TURN media servers, and continuous engineering."
  ),
  CrowdfundingSlide(
    MR.images.crowdfunding_4,
    "No ads, no trackers, no telemetry",
    "Zero remains free to use across iOS, Android, macOS, Windows, Linux, and CLI.",
    "Support development directly at simpl.global/donate."
  ),
)

@Composable
fun GetStakeView(showFirstImage: Boolean, inCenterOfWindow: Boolean = false, close: () -> Unit) {
  val uriHandler = LocalUriHandler.current
  val stopped = chatModel.chatRunning.value == false

  @Composable
  fun slideImage(slide: CrowdfundingSlide) {
    if (BuildConfigCommon.ZERO_ASSETS) {
      Image(
        painterResource(slide.image),
        contentDescription = null,
        contentScale = ContentScale.FillWidth,
        modifier = Modifier
          .widthIn(max = crowdfundingLayout.maxImageWidth)
          .fillMaxWidth()
          .clip(crowdfundingLayout.imageShape)
          .fullScreenOnClick(slide.image)
      )
    } else {
      Text(slide.heading, style = MaterialTheme.typography.h4, fontWeight = FontWeight.Medium)
      if (slide.info != null) {
        Text(slide.info, Modifier.padding(top = 4.dp), lineHeight = 24.sp)
      }
    }
  }

  ColumnWithScrollBar(Modifier.pinchZoom().padding(horizontal = DEFAULT_PADDING)) {
    val title = "Support\nZero"
    AppBarTitle(if (inCenterOfWindow) title.replace("\n", " ") else title, withPadding = false)
    if (showFirstImage) {
      slideImage(getStakeSlides[0])
    }
    Text(
      buildAnnotatedString {
        append(getStakeSlides[0].text)
        withLink(LinkAnnotation.Url(DONATE_URL) { uriHandler.openUriCatching(DONATE_URL) }) {
          withStyle(SpanStyle(color = MaterialTheme.colors.primary, fontWeight = FontWeight.Bold)) {
            append(" Donate via simpl.global/donate.")
          }
        }
      },
      Modifier.padding(top = if (showFirstImage) 8.dp else 0.dp),
      lineHeight = 24.sp
    )

    getStakeSlides.drop(1).forEach { slide ->
      Column(Modifier.padding(top = DEFAULT_PADDING * 1.5f)) {
        slideImage(slide)
        Text(slide.text, Modifier.padding(top = 8.dp), lineHeight = 24.sp)
      }
    }

    Column(
      Modifier.fillMaxWidth().padding(top = DEFAULT_PADDING * 2),
      horizontalAlignment = Alignment.CenterHorizontally
    ) {
      OnboardingActionButton(
        if (appPlatform.isAndroid) Modifier.fillMaxWidth() else Modifier.widthIn(min = 300.dp),
        labelId = MR.strings.v7_0_invest_learn_more,
        onboarding = null,
        onclick = { uriHandler.openUriCatching(DONATE_URL) }
      )
      if (!chatModel.desktopNoUserNoRemote) {
        TextButtonBelowOnboardingButton(
          "Visit simpl.global",
          onClick = if (stopped) null else ({
            close()
            uriHandler.openVerifiedZeroUri(SUPPORT_CONTACT_URI)
          })
        )
      }
    }
  }
}

@Composable
private fun Modifier.fullScreenOnClick(image: ImageResource): Modifier {
  if (!appPlatform.isDesktop) return this
  return pointerHoverIcon(PointerIcon.Hand).clickable(
    interactionSource = remember { MutableInteractionSource() },
    indication = null
  ) {
    ModalManager.fullscreen.showCustomModal { close ->
      BackHandler(onBack = close)
      Box(
        Modifier
          .fillMaxSize()
          .background(Color.Black)
          .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = close),
        contentAlignment = Alignment.Center
      ) {
        Image(painterResource(image), contentDescription = null, contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize())
      }
    }
  }
}

private const val MAX_PAGE_ZOOM = 5f

@Composable
private fun Modifier.pinchZoom(): Modifier {
  if (!appPlatform.isAndroid) return this
  var scale by remember { mutableStateOf(1f) }
  var offsetX by remember { mutableStateOf(0f) }
  var offsetY by remember { mutableStateOf(0f) }
  var size by remember { mutableStateOf(IntSize.Zero) }
  return this
    .onGloballyPositioned { size = it.size }
    .graphicsLayer {
      scaleX = scale
      scaleY = scale
      translationX = offsetX
      translationY = offsetY
    }
    .pointerInput(Unit) {
      awaitEachGesture {
        awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
        var taken: Boolean? = null
        do {
          val event = awaitPointerEvent(PointerEventPass.Initial)
          val multiTouch = event.changes.count { it.pressed } > 1
          if (multiTouch || scale > 1f) {
            scale = (scale * event.calculateZoom()).coerceIn(1f, MAX_PAGE_ZOOM)
            val pan = event.calculatePan()
            val maxX = size.width * (scale - 1f) / 2
            val maxY = size.height * (scale - 1f) / 2
            val pannedY = offsetY + pan.y * scale
            offsetX = (offsetX + pan.x * scale).coerceIn(-maxX, maxX)
            offsetY = pannedY.coerceIn(-maxY, maxY)
            if (multiTouch) taken = true
            else if (taken == null && pan.y != 0f) taken = pannedY.absoluteValue < maxY
            if (taken == true) event.changes.forEach { if (it.pressed) it.consume() }
          }
        } while (event.changes.any { it.pressed })
      }
    }
}

@Composable
fun CreateUpdateAddressShortLinkView(modalManager: ModalManager) {
  val clipboard = LocalClipboardManager.current
  val progressIndicator = remember { mutableStateOf(false) }

  fun share(userAddress: String) { clipboard.shareText(userAddress) }

  Column(modifier = Modifier.padding(bottom = 12.dp)) {
    Row(
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(8.dp),
      modifier = Modifier.padding(bottom = 4.dp)
    ) {
      Icon(painterResource(MR.images.ic_link), stringResource(MR.strings.v6_4_1_short_address), tint = MaterialTheme.colors.secondary)
      Text(
        generalGetString(MR.strings.v6_4_1_short_address),
        maxLines = 2,
        overflow = TextOverflow.Ellipsis,
        style = MaterialTheme.typography.h4,
        fontWeight = FontWeight.Medium,
        modifier = Modifier.padding(bottom = 6.dp)
      )
    }
    val addr = chatModel.userAddress.value
    if (addr != null) {
      if (addr.shouldBeUpgraded) {
        Row(
          verticalAlignment = Alignment.CenterVertically,
          horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
          Text(
            stringResource(MR.strings.v6_4_1_short_address_update),
            color = MaterialTheme.colors.primary,
            fontSize = 15.sp,
            modifier = Modifier
              .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null
              ) {
                showAddShortLinkAlert(progressIndicator = progressIndicator, share = ::share)
              }
          )
          if (progressIndicator.value) {
            CIFileViewScope.progressIndicator(sizeMultiplier = 0.5f)
          }
        }
      } else {
        Text(
          stringResource(MR.strings.v6_4_1_short_address_share),
          color = MaterialTheme.colors.primary,
          fontSize = 15.sp,
          modifier = Modifier
            .clickable(
              interactionSource = remember { MutableInteractionSource() },
              indication = null
            ) {
              share(addr.connLinkContact.zeroChatUri(short = true))
            }
        )
      }
    } else {
      Text(
        stringResource(MR.strings.v6_4_1_short_address_create),
        color = MaterialTheme.colors.primary,
        fontSize = 15.sp,
        modifier = Modifier
          .clickable(
            interactionSource = remember { MutableInteractionSource() },
            indication = null
          ) {
            modalManager.showModalCloseable { close ->
              UserAddressView(chatModel = chatModel, shareViaProfile = false, autoCreateAddress = true, close = close)
            }
          }
      )
    }
  }
}

@Preview

@Composable
fun PreviewWhatsNewView() {
  ZeroTheme {
    val data = remember { ModalData() }
    data.WhatsNewView(
      viaSettings = true,
      close = {}
    )
  }
}
