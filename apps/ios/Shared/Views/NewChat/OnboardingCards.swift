import SwiftUI
import Zero

struct OnboardingCardView: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var theme: AppTheme
    @AppStorage(DEFAULT_TOOLBAR_MATERIAL) private var toolbarMaterial = ToolbarMaterial.defaultMaterial
    let imageName: String
    let icon: String
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    let labelHeightRatio: CGFloat
    let action: () -> Void

    static let lightStops: [Gradient.Stop] = [
        .init(color: Color(red: 1.0, green: 1.0, blue: 1.0), location: 0.0),
        .init(color: Color(red: 0.961, green: 0.961, blue: 0.969), location: 0.45),
        .init(color: Color(red: 0.922, green: 0.922, blue: 0.929), location: 0.85),
        .init(color: Color(red: 0.886, green: 0.886, blue: 0.902), location: 1.0)
    ]

    static let darkStops: [Gradient.Stop] = [
        .init(color: Color(red: 0.039, green: 0.039, blue: 0.039), location: 0.0),
        .init(color: Color(red: 0.071, green: 0.071, blue: 0.078), location: 0.45),
        .init(color: Color(red: 0.102, green: 0.102, blue: 0.114), location: 0.85),
        .init(color: Color(red: 0.133, green: 0.133, blue: 0.149), location: 1.0)
    ]

    static let gradientAngle: Double = 80.0 * .pi / 180.0

    static func gradientPoints(aspectRatio: CGFloat, scale: CGFloat) -> (start: UnitPoint, end: UnitPoint) {
        let r = Double(aspectRatio)
        let s = Double(scale)
        let dx = cos(gradientAngle)
        let dy = -sin(gradientAngle) / r
        let dLenSq = dx * dx + dy * dy
        let projections = [
            -0.5 * dx + (-0.5) * dy,
             0.5 * dx + (-0.5) * dy,
            -0.5 * dx + 0.5 * dy,
             0.5 * dx + 0.5 * dy
        ]
        let tMin = projections.min()!
        let tMax = projections.max()!
        let startX = 0.5 + tMin * dx / dLenSq
        let startY = 0.5 + tMin * dy / dLenSq
        let endX = 0.5 + tMax * dx / dLenSq
        let endY = 0.5 + tMax * dy / dLenSq
        return (
            start: .init(x: 0.5 + (startX - 0.5) * s, y: 0.5 + (startY - 0.5) * s),
            end: .init(x: 0.5 + (endX - 0.5) * s, y: 0.5 + (endY - 0.5) * s)
        )
    }

    var body: some View {
        Button(action: action) {
            GeometryReader { geo in
                let labelHeight = geo.size.width * labelHeightRatio
                let imageHeight = max(geo.size.height - labelHeight, 1)
                let imageAspect = imageHeight / geo.size.width
                let gp = Self.gradientPoints(aspectRatio: imageAspect, scale: colorScheme == .light ? 1.2 : 1.5)
                VStack(spacing: 0) {
                    ZStack {
                        LinearGradient(
                            stops: colorScheme == .light ? Self.lightStops : Self.darkStops,
                            startPoint: gp.start,
                            endPoint: gp.end
                        )
                        #if ZERO_ASSETS
                        Image(colorScheme == .light ? imageName : "\(imageName)-light")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                        #else
                        Image(systemName: icon)
                            .font(.system(size: imageHeight * 0.25))
                            .foregroundColor(theme.colors.primary)
                        #endif
                    }
                    .frame(height: imageHeight)

                    labelRow(height: labelHeight)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
    }

    private func labelRow(height: CGFloat) -> some View {
        VStack {
            HStack {
                #if ZERO_ASSETS
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(theme.colors.primary)
                #endif
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(theme.colors.onBackground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundColor(theme.colors.onBackground.opacity(0.7))
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 16)
        .background(ToolbarMaterial.material(toolbarMaterial))
    }
}

private let backButtonHeight: CGFloat = 44

struct ConnectOnboardingView: View {
    @EnvironmentObject var m: ChatModel
    @EnvironmentObject var theme: AppTheme
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var currentPage = 0
    @State private var showConnectViaLink = false
    @State private var showInviteSomeone = false
    @State private var showCreateAddress = false
    @State private var showHybridConnect = false
    @State private var showAdvancedSettings = false
    @State private var showGuidedTutorial = false
    @State private var userPhrase: String = ZeroIdentityBridge.shared.currentPhrase ?? "Provisioning..."
    @State private var ephemeralCode: String? = nil
    @StateObject private var ss = SaveableSettings()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(theme.colors.background.isLightSurface ? "logo" : "logo-light")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 24)
                    .accessibilityLabel("Zero")
                Spacer()
                Button {
                    showGuidedTutorial = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.title3)
                        .foregroundColor(theme.colors.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Setup & Quick Guide")
                .padding(.trailing, 8)
                Button {
                    showAdvancedSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title3)
                        .foregroundColor(theme.colors.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            VStack(spacing: 8) {
                Text("Your 4-Word Zero Phrase")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(theme.colors.secondary)
                Text(userPhrase)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(theme.colors.onBackground)
                    .multilineTextAlignment(.center)
                    .onTapGesture {
                        UIPasteboard.general.string = userPhrase
                    }
                if let ephemeralCode {
                    Text("In-Person (5m): \(ephemeralCode)")
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        .foregroundColor(theme.colors.primary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(theme.colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(theme.colors.secondary.opacity(0.22), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 24)
            .padding(.top, 20)

            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 40))
                    .foregroundColor(theme.colors.primary)
                Text("Your conversations are secure.")
                    .font(.body)
                    .foregroundColor(theme.colors.secondary)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    showHybridConnect = true
                } label: {
                    Text("Connect (Phrase, Link, or 6-Digit Code)")
                        .font(.headline)
                        .foregroundColor(theme.colors.onPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            Capsule()
                                .fill(theme.colors.primary)
                        )
                }
                .buttonStyle(.plain)

                HStack(spacing: 16) {
                    Button {
                        Task {
                            let invite = m.userAddress?.connLinkContact.connFullLink ?? ""
                            if let code = try? await ZeroIdentityBridge.shared.provisionEphemeral6DigitCode(localCryptoInviteUrl: invite) {
                                await MainActor.run { ephemeralCode = code }
                            }
                        }
                    } label: {
                        Label("6-Digit Code", systemImage: "number.circle")
                            .font(.footnote)
                    }
                    Button {
                        showInviteSomeone = true
                    } label: {
                        Label("1-time link", systemImage: "link.badge.plus")
                            .font(.footnote)
                    }
                    Button {
                        showConnectViaLink = true
                    } label: {
                        Label("Scan QR", systemImage: "qrcode.viewfinder")
                            .font(.footnote)
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .onAppear {
            if let existing = ZeroIdentityBridge.shared.currentPhrase, ZeroIdentityBridge.isValid4WordPhrase(existing) {
                userPhrase = existing
            } else {
                Task {
                    let invite = m.userAddress?.connLinkContact.connFullLink ?? ""
                    if let res = try? await ZeroIdentityBridge.shared.provisionPhraseAndDeepLink(localCryptoInviteUrl: invite) {
                        await MainActor.run {
                            userPhrase = res.phrase
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showHybridConnect) {
            ZeroHybridConnectSheet()
                .environmentObject(theme)
        }
        .sheet(isPresented: $showGuidedTutorial) {
            ZeroGuidedTutorialView(allowSettingsShortcuts: true) {
                showGuidedTutorial = false
            }
            .environmentObject(m)
            .environmentObject(theme)
        }
        .sheet(isPresented: $showAdvancedSettings) {
            NavigationView {
                NetworkAndServers()
                    .navigationTitle("Network & servers")
                    .modifier(ThemedBackground(grouped: true))
                    .environmentObject(ss)
            }
        }
        .sheet(isPresented: $showConnectViaLink) {
            NavigationView {
                NewChatView(selection: .connect, showQRCodeScanner: true, onboarding: true)
                    .modifier(ThemedBackground(grouped: true))
            }
            .environment(\EnvironmentValues.refresh as! WritableKeyPath<EnvironmentValues, RefreshAction?>, nil)
        }
        .sheet(isPresented: $showInviteSomeone) {
            NavigationView {
                NewChatView(selection: .invite, onboarding: true)
                    .modifier(ThemedBackground(grouped: true))
            }
            .environment(\EnvironmentValues.refresh as! WritableKeyPath<EnvironmentValues, RefreshAction?>, nil)
        }
        .sheet(isPresented: $showCreateAddress) {
            NavigationView {
                UserAddressView(autoCreate: true, onboarding: true)
                    .modifier(ThemedBackground(grouped: true))
            }
            .environment(\EnvironmentValues.refresh as! WritableKeyPath<EnvironmentValues, RefreshAction?>, nil)
        }
    }

    @ViewBuilder
    private func cardPair<C1: View, C2: View>(
        _ geo: GeometryProxy,
        @ViewBuilder card1: () -> C1,
        @ViewBuilder card2: () -> C2
    ) -> some View {
        let padding: CGFloat = 20
        let spacing: CGFloat = 20
        let isLandscape = verticalSizeClass == .compact
        let cardWidth = isLandscape
            ? (geo.size.width - padding * 2 - spacing) / 2
            : geo.size.width - padding * 2
        let maxCardHeight = cardWidth * 0.75

        if isLandscape {
            HStack(spacing: spacing) {
                card1().frame(maxHeight: maxCardHeight)
                card2().frame(maxHeight: maxCardHeight)
            }
            .padding(.horizontal, padding)
        } else {
            VStack(spacing: spacing) {
                card1().frame(maxHeight: maxCardHeight)
                card2().frame(maxHeight: maxCardHeight)
            }
            .padding(.horizontal, padding)
        }
    }

    @ViewBuilder
    private func pageHeader(_ title: LocalizedStringKey, showBack: Bool) -> some View {
        let isLandscape = verticalSizeClass == .compact
        let titleView = Text(title)
            .font(.largeTitle)
            .bold()
            .lineLimit(1)
            .minimumScaleFactor(0.67)
            .frame(maxWidth: .infinity, alignment: .center)
        if isLandscape {
            ZStack(alignment: .leading) {
                if showBack { backButton }
                titleView
            }
            .padding(.horizontal, 16)
        } else {
            VStack(spacing: 0) {
                if showBack {
                    backButton.frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Color.clear.frame(height: backButtonHeight)
                }
                titleView
            }
            .padding(.horizontal, 16)
        }
    }

    private var backButton: some View {
        Button {
            withAnimation { currentPage = 0 }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text("Back")
            }
        }
        .frame(height: backButtonHeight)
    }

    private var talkToSomeonePage: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                pageHeader("Talk to someone", showBack: false)

                Spacer(minLength: 16)

                cardPair(geo) {
                    OnboardingCardView(
                        imageName: "card-let-someone-connect-to-you-alpha",
                        icon: "link.badge.plus",
                        title: "Let someone connect to you",
                        labelHeightRatio: 0.132,
                        action: { withAnimation { currentPage = 1 } }
                    )
                } card2: {
                    OnboardingCardView(
                        imageName: "card-connect-via-link-alpha",
                        icon: "qrcode.viewfinder",
                        title: "Connect via link or QR code",
                        labelHeightRatio: 0.132,
                        action: { showConnectViaLink = true }
                    )
                }

                Spacer(minLength: 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var connectWithSomeonePage: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                pageHeader("Create your link", showBack: true)

                Spacer(minLength: 16)

                cardPair(geo) {
                    OnboardingCardView(
                        imageName: "card-invite-someone-privately-alpha",
                        icon: "link.badge.plus",
                        title: "Invite someone privately",
                        subtitle: "A link for one person to connect",
                        labelHeightRatio: 0.195,
                        action: { showInviteSomeone = true }
                    )
                } card2: {
                    OnboardingCardView(
                        imageName: "card-create-your-public-address-alpha",
                        icon: "qrcode",
                        title: m.userAddress != nil ? "Your public address" : "Create your public address",
                        subtitle: "For anyone to reach you",
                        labelHeightRatio: 0.195,
                        action: { showCreateAddress = true }
                    )
                }

                Spacer(minLength: 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
