import SwiftUI
import UIKit
import Zero

private let bannerImageRatio: CGFloat = 800 / 505

struct ZeroHybridConnectSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var theme: AppTheme
    @State private var targetInput: String = ""
    @State private var isConnecting: Bool = false
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Connect Privately")
                    .font(.title3)
                    .bold()
                    .padding(.top, 24)

                Text("Enter a 4-word phrase, deep link (simpl.global/add/...), or 6-digit in-person code.")
                    .font(.footnote)
                    .foregroundColor(theme.colors.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                TextField("Crimson-Velvet-Horizon-Echo or 482-911", text: $targetInput)
                    .font(.system(.body, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .disableAutocorrection(true)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
                    .padding(.horizontal, 24)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                if isConnecting {
                    ProgressView("Resolving via Zero Broker...")
                        .padding(.top, 8)
                } else {
                    let canConnect = !targetInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    Button {
                        resolveAndConnect()
                    } label: {
                        Text("Connect")
                            .font(.headline)
                            .foregroundColor(canConnect ? theme.colors.onPrimary : .white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                Capsule()
                                    .fill(canConnect ? theme.colors.primary : Color.gray.opacity(0.4))
                            )
                    }
                    .disabled(targetInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.horizontal, 24)
                }

                Spacer()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func resolveAndConnect() {
        let cleaned = targetInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            errorMessage = "Enter a 4-word phrase, deep link, or 6-digit code."
            return
        }
        isConnecting = true
        errorMessage = nil
        Task {
            do {
                let inviteUri = try await ZeroIdentityBridge.shared.resolveIdentity(rawTarget: cleaned)
                await MainActor.run {
                    isConnecting = false
                    dismiss()
                    planAndConnect(inviteUri, theme: theme, dismiss: false)
                }
            } catch {
                await MainActor.run {
                    isConnecting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

struct ConnectBannerCard: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var theme: AppTheme
    @AppStorage(DEFAULT_TOOLBAR_MATERIAL) private var toolbarMaterial = ToolbarMaterial.defaultMaterial
    @AppStorage(DEFAULT_ADDRESS_CREATION_CARD_SHOWN) private var addressCreationCardShown = false
    @State private var showNewLink = false
    @State private var showPasteLink = false
    @State private var showHybridConnect = false
    @State private var showAdvancedNetwork = false
    @State private var showGuidedTutorial = false
    @State private var phrase: String = ZeroIdentityBridge.shared.currentPhrase ?? "Provisioning..."
    @State private var deepLink: String = ZeroIdentityBridge.shared.currentDeepLink ?? ""
    @State private var ephemeralCode: String? = nil
    @State private var copiedLabel: String? = nil
    @StateObject private var ss = SaveableSettings()

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            VStack(spacing: 10) {
                HStack {
                    Text(copiedLabel ?? "Your 4-Word Zero Phrase")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(copiedLabel != nil ? theme.colors.primary : theme.colors.secondary)
                    Spacer()
                    Button {
                        showGuidedTutorial = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(theme.colors.primary)
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Setup & Quick Guide")
                    Button {
                        showAdvancedNetwork = true
                    } label: {
                        Text("⚙️")
                            .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                    Button {
                        withAnimation { addressCreationCardShown = true }
                    } label: {
                        Image(systemName: "multiply")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(theme.colors.secondary)
                            .frame(width: 26, height: 26)
                            .background(theme.colors.onBackground.opacity(0.08), in: Circle())
                    }
                }

                Button {
                    UIPasteboard.general.string = phrase
                    showCopiedToast("4-Word Phrase Copied")
                } label: {
                    HStack(spacing: 8) {
                        Text(phrase)
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(theme.colors.onBackground)
                            .multilineTextAlignment(.center)
                        Image(systemName: "doc.on.doc")
                            .font(.footnote)
                            .foregroundColor(theme.colors.primary)
                    }
                }
                .buttonStyle(.plain)

                if let ephemeralCode {
                    Text("In-Person (5m): \(ephemeralCode)")
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        .foregroundColor(theme.colors.primary)
                }

                HStack(spacing: 8) {
                    Button {
                        let link = deepLink.isEmpty
                            ? "\(ZeroIdentityBridge.deepLinkPrefix)\(phrase.lowercased().replacingOccurrences(of: "-", with: ""))"
                            : deepLink
                        UIPasteboard.general.string = link
                        showCopiedToast("Deep Link Copied")
                    } label: {
                        Text("Copy Link")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(theme.colors.secondary.opacity(0.35), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        generateInPersonCode()
                    } label: {
                        Text("6-Digit Code")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(theme.colors.secondary.opacity(0.35), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    showHybridConnect = true
                } label: {
                    Text("Connect (Phrase, Link, or 6-Digit Code)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(theme.colors.onPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            Capsule()
                                .fill(theme.colors.primary)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(ToolbarMaterial.material(toolbarMaterial))
            )

            HStack(spacing: 2) {
                bannerHalf(
                    imageName: "banner-create-link",
                    icon: "link.badge.plus",
                    title: "New 1-time link",
                    action: { showNewLink = true }
                )
                bannerHalf(
                    imageName: "banner-paste-link",
                    icon: "qrcode.viewfinder",
                    title: "Paste link / Scan",
                    action: { showPasteLink = true }
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .onAppear {
            ensurePhraseLoaded()
        }
        .sheet(isPresented: $showHybridConnect) {
            ZeroHybridConnectSheet()
                .environmentObject(theme)
        }
        .sheet(isPresented: $showGuidedTutorial) {
            ZeroGuidedTutorialView(allowSettingsShortcuts: true) {
                showGuidedTutorial = false
            }
            .environmentObject(ChatModel.shared)
            .environmentObject(theme)
        }
        .sheet(isPresented: $showAdvancedNetwork) {
            NavigationView {
                NetworkAndServers()
                    .navigationTitle("Network & servers")
                    .modifier(ThemedBackground(grouped: true))
                    .environmentObject(ss)
            }
        }
        .sheet(isPresented: $showNewLink) {
            NavigationView {
                NewChatView(selection: .invite)
                    .modifier(ThemedBackground(grouped: true))
            }
        }
        .sheet(isPresented: $showPasteLink) {
            NavigationView {
                NewChatView(selection: .connect, showQRCodeScanner: true)
                    .modifier(ThemedBackground(grouped: true))
            }
        }
    }

    private func showCopiedToast(_ label: String) {
        copiedLabel = label
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            copiedLabel = nil
        }
    }

    private func ensurePhraseLoaded() {
        if let existing = ZeroIdentityBridge.shared.currentPhrase, ZeroIdentityBridge.isValid4WordPhrase(existing) {
            phrase = existing
            deepLink = ZeroIdentityBridge.shared.currentDeepLink ?? ""
            return
        }
        Task {
            let invite = ChatModel.shared.userAddress?.connLinkContact.connFullLink ?? ""
            if let provisioned = try? await ZeroIdentityBridge.shared.provisionPhraseAndDeepLink(localCryptoInviteUrl: invite) {
                await MainActor.run {
                    phrase = provisioned.phrase
                    deepLink = provisioned.deepLink
                }
            }
        }
    }

    private func generateInPersonCode() {
        Task {
            let invite = ChatModel.shared.userAddress?.connLinkContact.connFullLink ?? ""
            if let code = try? await ZeroIdentityBridge.shared.provisionEphemeral6DigitCode(localCryptoInviteUrl: invite) {
                await MainActor.run {
                    ephemeralCode = code
                }
            }
        }
    }

    @ViewBuilder
    private func bannerHalf(imageName: String, icon: String, title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                #if ZERO_ASSETS
                Image(colorScheme == .light ? imageName : "\(imageName)-light")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                #else
                gradientFallback(icon: icon)
                #endif
                HStack(spacing: 8) {
                    #if ZERO_ASSETS
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(theme.colors.primary)
                    #endif
                    Text(title)
                        .font(.footnote)
                        .foregroundColor(theme.colors.onBackground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(height: 20)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(ToolbarMaterial.material(toolbarMaterial))
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func gradientFallback(icon: String) -> some View {
        let gp = OnboardingCardView.gradientPoints(
            aspectRatio: 1 / bannerImageRatio,
            scale: colorScheme == .light ? 1.2 : 1.5
        )
        ZStack {
            LinearGradient(
                stops: colorScheme == .light ? OnboardingCardView.lightStops : OnboardingCardView.darkStops,
                startPoint: gp.start,
                endPoint: gp.end
            )
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(theme.colors.primary)
        }
        .aspectRatio(bannerImageRatio, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }
}
