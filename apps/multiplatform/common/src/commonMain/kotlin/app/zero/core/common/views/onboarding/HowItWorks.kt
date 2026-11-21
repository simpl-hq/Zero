package app.zero.core.common.views.onboarding

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.desktop.ui.tooling.preview.Preview
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalUriHandler
import dev.icerock.moko.resources.ImageResource
import dev.icerock.moko.resources.compose.painterResource
import dev.icerock.moko.resources.compose.stringResource
import androidx.compose.ui.text.*
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.zero.core.common.AppLock
import app.zero.core.common.model.*
import app.zero.core.common.model.ChatController.appPrefs
import app.zero.core.common.platform.*
import app.zero.core.common.ui.theme.*
import app.zero.core.common.views.chat.item.MarkdownText
import app.zero.core.common.views.chatlist.ZeroConnectByPinDialog
import app.zero.core.common.views.database.DatabaseView
import app.zero.core.common.views.helpers.*
import app.zero.core.common.views.chatlist.connectIfOpenedViaUri
import app.zero.core.common.views.usersettings.PrivacySettingsView
import app.zero.core.common.views.usersettings.networkAndServers.NetworkAndServersView
import app.zero.core.network.ZeroIdentityBridge
import app.zero.core.res.MR
import dev.icerock.moko.resources.StringResource

// step data model for guided setup tutorial
private data class GuidedTutorialHighlight(
  val icon: ImageResource,
  val heading: String,
  val detail: String
)

private data class GuidedTutorialStep(
  val icon: ImageResource,
  val eyebrow: String,
  val title: String,
  val summary: String,
  val highlights: List<GuidedTutorialHighlight>
)

// opens interactive guided setup tutorial in full screen across android and desktop
fun openZeroGuidedTutorial(
  allowSettingsShortcuts: Boolean = true,
  initialPhrase: String? = null,
  onComplete: (() -> Unit)? = null
) {
  ModalManager.fullscreen.showCustomModal(animated = true, forceAnimated = appPlatform.isDesktop) { close ->
    Box(
      Modifier
        .fillMaxSize()
        .background(MaterialTheme.colors.background)
        .systemBarsPadding()
    ) {
      BackHandler(enabled = true, onBack = close)
      ZeroGuidedTutorialView(
        allowSettingsShortcuts = allowSettingsShortcuts,
        initialPhrase = initialPhrase,
        onComplete = {
          onComplete?.invoke()
          close()
        }
      )
    }
  }
}

// interactive guided setup and usage tutorial across platforms
@Composable
fun ZeroGuidedTutorialView(
  allowSettingsShortcuts: Boolean = true,
  initialPhrase: String? = null,
  model: ChatModel = chatModel,
  onComplete: (() -> Unit)? = null
) {
  val clipboardManager = LocalClipboardManager.current
  val savedPhrase by remember { appPrefs.zeroAccountPin.state }
  val identityBridge = remember { ZeroIdentityBridge() }

  var currentStep by rememberSaveable { mutableStateOf(0) }
  var phrase by rememberSaveable { mutableStateOf(initialPhrase?.takeIf { it.isNotBlank() } ?: savedPhrase ?: "") }
  var deepLink by rememberSaveable { mutableStateOf("") }
  var ephemeralCode by rememberSaveable { mutableStateOf<String?>(null) }
  var statusBanner by rememberSaveable { mutableStateOf<String?>(null) }
  var isGeneratingCode by remember { mutableStateOf(false) }
  var backedUpPhrase by rememberSaveable { mutableStateOf(false) }
  var showConnectDialog by rememberSaveable { mutableStateOf(false) }

  val isDesktop = appPlatform.isDesktop
  val steps = remember(isDesktop) {
    listOf(
      GuidedTutorialStep(
        icon = MR.images.ic_vpn_key_filled,
        eyebrow = "STEP 1 · NO ACCOUNTS",
        title = "Your Zero Identity",
        summary = "Zero never uses phone numbers, emails, or server accounts. Everything lives encrypted locally on your device.",
        highlights = listOf(
          GuidedTutorialHighlight(
            icon = MR.images.ic_vpn_key_filled,
            heading = "4-Word Phrase",
            detail = "Share your phrase or simpl.global/add link so contacts can reach you without any central directory."
          ),
          GuidedTutorialHighlight(
            icon = MR.images.ic_verified_user,
            heading = "One-Way Queues",
            detail = "Contacts write into isolated queues on your relay while your replies go strictly to theirs."
          )
        )
      ),
      GuidedTutorialStep(
        icon = MR.images.ic_add_link,
        eyebrow = "STEP 2 · CONNECT",
        title = "Three Ways to Pair",
        summary = if (isDesktop) {
          "Pick whichever handoff fits: paste an invite link or phrase directly, share a 5-minute verbal code, or scan with mobile."
        } else {
          "Pick whichever handoff fits how you meet: remote links, fast 6-digit verbal codes, or camera QR scans."
        },
        highlights = listOf(
          GuidedTutorialHighlight(
            icon = MR.images.ic_person_add,
            heading = "6-Digit Code (5 min)",
            detail = "Mint a short expiring code when pairing side by side or over a voice call."
          ),
          GuidedTutorialHighlight(
            icon = MR.images.ic_qr_code_scanner,
            heading = "1-Time Link & QR",
            detail = "Create single-use links when sharing publicly so nobody else can reuse the invite."
          )
        )
      ),
      GuidedTutorialStep(
        icon = MR.images.ic_shield,
        eyebrow = "STEP 3 · METADATA",
        title = "Private Routing & Media",
        summary = "Every message travels as a fixed 16 KB encrypted packet with Curve448 + sntrup761 post-quantum keys.",
        highlights = listOf(
          GuidedTutorialHighlight(
            icon = MR.images.ic_wifi_tethering,
            heading = "2-Hop Onion Mode",
            detail = "Hide your IP address from recipient relays via a forwarding hop in Network & servers."
          ),
          GuidedTutorialHighlight(
            icon = MR.images.ic_settings_ethernet,
            heading = "XFTP Media Transfers",
            detail = "Images, voice clips, and files upload encrypted in chunks and auto-expire off relays."
          )
        )
      ),
      GuidedTutorialStep(
        icon = MR.images.ic_lock,
        eyebrow = "STEP 4 · SOVEREIGNTY",
        title = if (isDesktop) "Secure This Computer" else "Lock Your Device",
        summary = "Because Zero servers keep no message history, locking the device in front of you protects everything.",
        highlights = listOf(
          GuidedTutorialHighlight(
            icon = MR.images.ic_lock,
            heading = if (isDesktop) "Passcode & Screen Privacy" else "Biometric Lock & Screen Blur",
            detail = if (isDesktop) {
              "Enable passcode lock in Privacy and keep OS disk encryption active."
            } else {
              "Enable biometric unlock and hide previews in recent apps under Privacy."
            }
          ),
          GuidedTutorialHighlight(
            icon = MR.images.ic_desktop,
            heading = "Database Passphrase & Backups",
            detail = "Review SQLCipher key storage and export an encrypted backup before switching devices."
          )
        )
      )
    )
  }

  LaunchedEffect(savedPhrase, initialPhrase) {
    val active = initialPhrase?.takeIf { it.isNotBlank() } ?: savedPhrase ?: ""
    if (active.isNotBlank()) {
      phrase = active
      if (deepLink.isBlank()) {
        deepLink = "${ZeroIdentityBridge.DEEP_LINK_PREFIX}${active.lowercase().replace("-", "")}"
      }
    } else if (allowSettingsShortcuts) {
      withBGApi {
        val connLink = model.controller.apiCreateOrGetSilentUserAddress(model.remoteHostId())
        val inviteUrl = connLink?.connShortLink ?: connLink?.connFullLink ?: "zero:/contact"
        val res = runCatching { identityBridge.provisionPhraseAndDeepLink(inviteUrl) }.getOrNull()
        if (res != null) {
          phrase = res.phrase
          deepLink = res.deepLink
          appPrefs.zeroAccountPin.set(res.phrase)
        } else {
          showToast("Connect to network to provision phrase")
        }
      }
    }
  }

  fun showToast(msg: String) {
    statusBanner = msg
  }

  Box(
    modifier = Modifier
      .fillMaxSize()
      .background(MaterialTheme.colors.background),
    contentAlignment = Alignment.TopCenter
  ) {
    Column(
      modifier = Modifier
        .widthIn(max = 580.dp)
        .fillMaxSize()
    ) {
      // top bar with step counter and skip/done trigger
      Row(
        modifier = Modifier
          .fillMaxWidth()
          .padding(horizontal = 20.dp, vertical = 14.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
      ) {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
          Text(
            "Setup & Quick Guide",
            style = MaterialTheme.typography.h2,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colors.onBackground
          )
          Text(
            "Step ${currentStep + 1} of ${steps.size}",
            fontSize = 12.sp,
            color = MaterialTheme.colors.secondary
          )
        }
        TextButton(onClick = { onComplete?.invoke() }) {
          Text(
            if (allowSettingsShortcuts) "Done" else "Skip",
            color = MaterialTheme.colors.primary,
            fontWeight = FontWeight.Medium
          )
        }
      }

      // 4-segment progress indicator
      Row(
        modifier = Modifier
          .fillMaxWidth()
          .padding(horizontal = 20.dp)
          .padding(bottom = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp)
      ) {
        steps.indices.forEach { idx ->
          Box(
            modifier = Modifier
              .weight(1f)
              .height(4.dp)
              .clip(CircleShape)
              .background(
                if (idx <= currentStep) MaterialTheme.colors.primary
                else MaterialTheme.colors.secondary.copy(alpha = 0.22f)
              )
          )
        }
      }

      Column(
        modifier = Modifier
          .weight(1f)
          .verticalScroll(rememberScrollState())
          .padding(horizontal = 20.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
      ) {
        val step = steps[currentStep]
        // step summary card
        Surface(
          shape = RoundedCornerShape(18.dp),
          color = MaterialTheme.colors.surface,
          border = BorderStroke(1.dp, MaterialTheme.colors.secondary.copy(alpha = 0.16f)),
          modifier = Modifier.fillMaxWidth()
        ) {
          Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
          ) {
            Row(
              horizontalArrangement = Arrangement.spacedBy(12.dp),
              verticalAlignment = Alignment.CenterVertically
            ) {
              Box(
                modifier = Modifier
                  .size(44.dp)
                  .clip(RoundedCornerShape(12.dp))
                  .background(MaterialTheme.colors.primary.copy(alpha = 0.14f)),
                contentAlignment = Alignment.Center
              ) {
                Icon(
                  painterResource(step.icon),
                  contentDescription = null,
                  tint = MaterialTheme.colors.primary,
                  modifier = Modifier.size(22.dp)
                )
              }
              Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                  step.eyebrow,
                  fontSize = 11.sp,
                  fontWeight = FontWeight.SemiBold,
                  fontFamily = FontFamily.Monospace,
                  color = MaterialTheme.colors.secondary
                )
                Text(
                  step.title,
                  style = MaterialTheme.typography.h2,
                  fontWeight = FontWeight.Bold,
                  color = MaterialTheme.colors.onSurface
                )
              }
            }

            Text(
              step.summary,
              style = MaterialTheme.typography.body2,
              lineHeight = 20.sp,
              color = MaterialTheme.colors.onSurface.copy(alpha = 0.88f)
            )

            step.highlights.forEach { item ->
              Surface(
                shape = RoundedCornerShape(12.dp),
                color = MaterialTheme.colors.background.copy(alpha = 0.65f),
                modifier = Modifier.fillMaxWidth()
              ) {
                Row(
                  modifier = Modifier.padding(12.dp),
                  horizontalArrangement = Arrangement.spacedBy(10.dp),
                  verticalAlignment = Alignment.Top
                ) {
                  Icon(
                    painterResource(item.icon),
                    contentDescription = null,
                    tint = MaterialTheme.colors.primary,
                    modifier = Modifier.size(20.dp).padding(top = 2.dp)
                  )
                  Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                      item.heading,
                      fontWeight = FontWeight.SemiBold,
                      fontSize = 14.sp,
                      color = MaterialTheme.colors.onSurface
                    )
                    Text(
                      item.detail,
                      fontSize = 12.sp,
                      lineHeight = 17.sp,
                      color = MaterialTheme.colors.secondary
                    )
                  }
                }
              }
            }
          }
        }

        // step-specific interactive actions
        when (currentStep) {
          0 -> {
            val displayPhrase = phrase.ifBlank { "Provisioning phrase..." }
            Surface(
              shape = RoundedCornerShape(16.dp),
              color = MaterialTheme.colors.surface,
              border = BorderStroke(1.dp, MaterialTheme.colors.secondary.copy(alpha = 0.16f)),
              modifier = Modifier.fillMaxWidth()
            ) {
              Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
              ) {
                Row(
                  modifier = Modifier.fillMaxWidth(),
                  horizontalArrangement = Arrangement.SpaceBetween,
                  verticalAlignment = Alignment.CenterVertically
                ) {
                  Text(
                    statusBanner ?: "YOUR ACTIVE 4-WORD PHRASE",
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                    fontFamily = FontFamily.Monospace,
                    color = if (statusBanner != null) MaterialTheme.colors.primary else MaterialTheme.colors.secondary
                  )
                  if (phrase.isNotBlank()) {
                    TextButton(
                      onClick = {
                        clipboardManager.setText(AnnotatedString(phrase))
                        showToast("4-WORD PHRASE COPIED")
                      },
                      contentPadding = PaddingValues(horizontal = 8.dp, vertical = 2.dp)
                    ) {
                      Icon(
                        painterResource(MR.images.ic_content_copy),
                        contentDescription = null,
                        tint = MaterialTheme.colors.primary,
                        modifier = Modifier.size(14.dp)
                      )
                      Spacer(Modifier.width(4.dp))
                      Text("Copy", fontSize = 12.sp, color = MaterialTheme.colors.primary)
                    }
                  }
                }
                Text(
                  displayPhrase,
                  fontSize = 18.sp,
                  fontWeight = FontWeight.Bold,
                  fontFamily = FontFamily.Monospace,
                  color = MaterialTheme.colors.onSurface
                )
                if (deepLink.isNotBlank()) {
                  Text(
                    deepLink,
                    fontSize = 12.sp,
                    fontFamily = FontFamily.Monospace,
                    color = MaterialTheme.colors.primary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.clickable {
                      clipboardManager.setText(AnnotatedString(deepLink))
                      showToast("INVITE LINK COPIED")
                    }
                  )
                }
              }
            }
          }

          1 -> {
            Surface(
              shape = RoundedCornerShape(16.dp),
              color = MaterialTheme.colors.surface,
              border = BorderStroke(1.dp, MaterialTheme.colors.secondary.copy(alpha = 0.16f)),
              modifier = Modifier.fillMaxWidth()
            ) {
              Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
              ) {
                Text(
                  statusBanner ?: "TRY PAIRING TOOLS",
                  fontSize = 11.sp,
                  fontWeight = FontWeight.SemiBold,
                  fontFamily = FontFamily.Monospace,
                  color = if (statusBanner != null) MaterialTheme.colors.primary else MaterialTheme.colors.secondary
                )
                AnimatedVisibility(visible = ephemeralCode != null) {
                  val code = ephemeralCode ?: ""
                  Surface(
                    shape = RoundedCornerShape(10.dp),
                    color = MaterialTheme.colors.background.copy(alpha = 0.65f),
                    modifier = Modifier.fillMaxWidth()
                  ) {
                    Row(
                      modifier = Modifier.padding(10.dp),
                      horizontalArrangement = Arrangement.SpaceBetween,
                      verticalAlignment = Alignment.CenterVertically
                    ) {
                      Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text("Live 5-min Code:", fontSize = 12.sp, color = MaterialTheme.colors.secondary)
                        Text(
                          code,
                          fontSize = 17.sp,
                          fontWeight = FontWeight.Bold,
                          fontFamily = FontFamily.Monospace,
                          color = MaterialTheme.colors.primary
                        )
                      }
                      Text(
                        "Copy",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colors.primary,
                        modifier = Modifier.clickable {
                          clipboardManager.setText(AnnotatedString(code))
                          showToast("6-DIGIT CODE COPIED")
                        }
                      )
                    }
                  }
                }
                Row(
                  modifier = Modifier.fillMaxWidth(),
                  horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                  OutlinedButton(
                    onClick = {
                      if (!isGeneratingCode) {
                        isGeneratingCode = true
                        withBGApi {
                          val connLink = model.controller.apiCreateOrGetSilentUserAddress(model.remoteHostId())
                          val inviteUrl = connLink?.connShortLink ?: connLink?.connFullLink ?: "zero:/contact"
                          val code = runCatching {
                            identityBridge.provisionEphemeral6DigitCode(inviteUrl).code
                          }.getOrNull()
                          isGeneratingCode = false
                          if (code != null) {
                            ephemeralCode = code
                            showToast("6-DIGIT CODE READY")
                          } else {
                            showToast("Connect to network to mint 6-digit code")
                          }
                        }
                      }
                    },
                    enabled = !isGeneratingCode,
                    shape = RoundedCornerShape(10.dp),
                    modifier = Modifier.weight(1f).height(42.dp)
                  ) {
                    Text(if (isGeneratingCode) "Minting..." else "6-Digit Code", fontSize = 13.sp, maxLines = 1)
                  }
                  if (allowSettingsShortcuts) {
                    Button(
                      onClick = { showConnectDialog = true },
                      shape = RoundedCornerShape(999.dp),
                      elevation = ButtonDefaults.elevation(0.dp, 0.dp, 0.dp, 0.dp),
                      colors = ButtonDefaults.buttonColors(backgroundColor = MaterialTheme.colors.primary),
                      modifier = Modifier.weight(1f).height(42.dp)
                    ) {
                      Text("Connect Now", color = MaterialTheme.colors.onPrimary, fontSize = 13.sp, maxLines = 1)
                    }
                  }
                }
              }
            }
          }

          2 -> {
            if (allowSettingsShortcuts) {
              TutorialActionRow(
                icon = MR.images.ic_wifi_tethering,
                title = "Open Network & Servers",
                subtitle = "Review relay routing & 2-hop onion privacy"
              ) {
                ModalManager.fullscreen.showCustomModal(animated = true, forceAnimated = appPlatform.isDesktop) { close ->
                  NetworkAndServersView(close)
                }
              }
            }
          }

          else -> {
            Surface(
              shape = RoundedCornerShape(16.dp),
              color = MaterialTheme.colors.surface,
              border = BorderStroke(1.dp, MaterialTheme.colors.secondary.copy(alpha = 0.16f)),
              modifier = Modifier.fillMaxWidth()
            ) {
              Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
              ) {
                Row(
                  modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(10.dp))
                    .clickable { backedUpPhrase = !backedUpPhrase }
                    .padding(vertical = 4.dp),
                  horizontalArrangement = Arrangement.spacedBy(10.dp),
                  verticalAlignment = Alignment.CenterVertically
                ) {
                  Icon(
                    painterResource(
                      if (backedUpPhrase) MR.images.ic_check_circle_filled else MR.images.ic_radio_button_unchecked
                    ),
                    contentDescription = null,
                    tint = if (backedUpPhrase) MaterialTheme.colors.primary else MaterialTheme.colors.secondary,
                    modifier = Modifier.size(22.dp)
                  )
                  Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                      "I saved my 4-word phrase safely",
                      fontSize = 14.sp,
                      fontWeight = FontWeight.Medium,
                      color = MaterialTheme.colors.onSurface
                    )
                    Text(
                      "Check it anytime under Settings -> Help -> About Zero.",
                      fontSize = 12.sp,
                      color = MaterialTheme.colors.secondary
                    )
                  }
                }

                if (allowSettingsShortcuts) {
                  TutorialActionRow(
                    icon = MR.images.ic_lock,
                    title = if (isDesktop) "Open Privacy & App Lock" else "Open Privacy & Biometric Lock",
                    subtitle = "Configure passcode, screen privacy & blur"
                  ) {
                    ModalManager.fullscreen.showModal(settings = true, cardScreen = true, forceAnimated = appPlatform.isDesktop) {
                      PrivacySettingsView(
                        chatModel = model,
                        showSettingsModal = { modalView ->
                          {
                            ModalManager.fullscreen.showModal(settings = true, cardScreen = true, forceAnimated = appPlatform.isDesktop) {
                              modalView(model)
                            }
                          }
                        },
                        setPerformLA = AppLock::setPerformLA
                      )
                    }
                  }
                  TutorialActionRow(
                    icon = MR.images.ic_desktop,
                    title = "Open Database & Passphrase",
                    subtitle = "Manage SQLCipher key storage & archive backups"
                  ) {
                    ModalManager.fullscreen.showModal(settings = true, cardScreen = true, forceAnimated = appPlatform.isDesktop) {
                      DatabaseView()
                    }
                  }
                }
              }
            }
          }
        }
      }

      // bottom back and continue buttons
      Row(
        modifier = Modifier
          .fillMaxWidth()
          .padding(horizontal = 20.dp, vertical = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp)
      ) {
        if (currentStep > 0) {
          OutlinedButton(
            onClick = {
              currentStep -= 1
              statusBanner = null
            },
            shape = RoundedCornerShape(14.dp),
            modifier = Modifier.weight(0.36f).height(48.dp)
          ) {
            Text("Back")
          }
        }
        Button(
          onClick = {
            statusBanner = null
            if (currentStep < steps.lastIndex) {
              currentStep += 1
            } else {
              onComplete?.invoke()
            }
          },
          shape = RoundedCornerShape(999.dp),
          elevation = ButtonDefaults.elevation(0.dp, 0.dp, 0.dp, 0.dp),
          colors = ButtonDefaults.buttonColors(backgroundColor = MaterialTheme.colors.primary),
          modifier = Modifier.weight(0.64f).height(48.dp)
        ) {
          Text(
            if (currentStep < steps.lastIndex) "Next Step" else "Start Using Zero",
            color = MaterialTheme.colors.onPrimary,
            fontWeight = FontWeight.SemiBold
          )
        }
      }
    }
  }

  if (showConnectDialog) {
    ZeroConnectByPinDialog(
      onDismiss = { showConnectDialog = false },
      onConnectPin = { target ->
        showConnectDialog = false
        withBGApi {
          val inviteUrl = runCatching { identityBridge.resolveIdentity(target) }.getOrNull()
          if (inviteUrl != null) {
            connectIfOpenedViaUri(model.remoteHostId(), inviteUrl, model)
            onComplete?.invoke()
          } else {
            showToast("COULD NOT FIND CONTACT CODE")
          }
        }
      }
    )
  }
}

// reusable navigation row inside tutorial steps
@Composable
private fun TutorialActionRow(
  icon: ImageResource,
  title: String,
  subtitle: String,
  onClick: () -> Unit
) {
  Surface(
    shape = RoundedCornerShape(12.dp),
    color = MaterialTheme.colors.background.copy(alpha = 0.65f),
    border = BorderStroke(1.dp, MaterialTheme.colors.secondary.copy(alpha = 0.14f)),
    modifier = Modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(12.dp))
      .clickable(onClick = onClick)
  ) {
    Row(
      modifier = Modifier.padding(14.dp),
      horizontalArrangement = Arrangement.spacedBy(12.dp),
      verticalAlignment = Alignment.CenterVertically
    ) {
      Icon(
        painterResource(icon),
        contentDescription = null,
        tint = MaterialTheme.colors.primary,
        modifier = Modifier.size(22.dp)
      )
      Column(
        modifier = Modifier.weight(1f),
        verticalArrangement = Arrangement.spacedBy(2.dp)
      ) {
        Text(
          title,
          fontSize = 14.sp,
          fontWeight = FontWeight.SemiBold,
          color = MaterialTheme.colors.onSurface
        )
        Text(
          subtitle,
          fontSize = 12.sp,
          color = MaterialTheme.colors.secondary
        )
      }
      Icon(
        painterResource(MR.images.ic_arrow_forward),
        contentDescription = null,
        tint = MaterialTheme.colors.secondary,
        modifier = Modifier.size(16.dp)
      )
    }
  }
}

@Composable
fun HowItWorks(user: User?, onboardingStage: SharedPreference<OnboardingStage>? = null) {
  Column(Modifier.fillMaxSize().padding(horizontal = if (appPlatform.isDesktop) DEFAULT_PADDING * 2 else DEFAULT_PADDING)) {
    Spacer(Modifier.statusBarsPadding().padding(top = AppBarHeight * fontSizeSqrtMultiplier))
    val paraPadding = PaddingValues(bottom = if (appPlatform.isDesktop) 10.dp else 12.dp)
    Column(Modifier.weight(1f).padding(bottom = DEFAULT_PADDING).verticalScroll(rememberScrollState())) {
      Text(stringResource(MR.strings.why_built_heading), style = MaterialTheme.typography.h1, modifier = Modifier.padding(bottom = DEFAULT_PADDING))
      ReadableText(MR.strings.why_built_p1, padding = paraPadding)
      ReadableText(MR.strings.why_built_p2, padding = paraPadding)
      ReadableText(MR.strings.why_built_p3, padding = paraPadding)
      ReadableText(MR.strings.why_built_p4, padding = paraPadding)
      ReadableText(MR.strings.why_built_p5, padding = paraPadding)
      ReadableText(MR.strings.why_built_p6, padding = paraPadding)
      ReadableText(MR.strings.why_built_p7, padding = paraPadding)
      ReadableText(MR.strings.why_built_tagline, padding = paraPadding)
    }
    if (onboardingStage != null) {
      Column(
        Modifier.widthIn(max = if (appPlatform.isAndroid) 450.dp else 1000.dp).align(Alignment.CenterHorizontally),
        horizontalAlignment = Alignment.CenterHorizontally
      ) {
        OnboardingActionButton(user, onboardingStage, onclick = { ModalManager.fullscreen.closeModal() })
        TextButtonBelowOnboardingButton("", null)
      }
    }
  }
}

@Composable
fun ReadableText(stringResId: StringResource, textAlign: TextAlign = TextAlign.Start, padding: PaddingValues = PaddingValues(bottom = 12.dp), style: TextStyle = LocalTextStyle.current, args: Any? = null) {
  Text(annotatedStringResource(stringResId, args), modifier = Modifier.padding(padding), textAlign = textAlign, lineHeight = 22.sp, style = style)
}

@Composable
fun ReadableTextWithLink(stringResId: StringResource, link: String, textAlign: TextAlign = TextAlign.Start, padding: PaddingValues = PaddingValues(bottom = 12.dp), zeroLink: Boolean = false) {
  val annotated = annotatedStringResource(stringResId)
  val primary = MaterialTheme.colors.primary
  val newStyles = remember(stringResId) {
    val newStyles = ArrayList<AnnotatedString.Range<SpanStyle>>()
    annotated.spanStyles.forEach {
      if (it.item.color == ZeroBlue) {
        newStyles.add(it.copy(item = it.item.copy(primary)))
      } else {
        newStyles.add(it)
      }
    }
    newStyles
  }
  val uriHandler = LocalUriHandler.current
  Text(AnnotatedString(annotated.text, newStyles), modifier = Modifier.padding(padding).clickable { if (zeroLink) uriHandler.openVerifiedZeroUri(link) else uriHandler.openExternalLink(link) }, textAlign = textAlign, lineHeight = 22.sp)
}

@Composable
fun ReadableText(text: String, textAlign: TextAlign = TextAlign.Start, padding: PaddingValues = PaddingValues(bottom = 12.dp)) {
  Text(text, modifier = Modifier.padding(padding), textAlign = textAlign, lineHeight = 22.sp)
}

@Preview

@Composable
fun PreviewHowItWorks() {
  ZeroTheme {
    HowItWorks(user = null)
  }
}
