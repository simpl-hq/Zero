import SwiftUI
import StoreKit
import Zero

private struct VersionDescription {
    var version: String
    var post: URL?
    var features: [Feature]
}

private enum Feature: Identifiable {
    case feature(Description)
    case view(FeatureView)

    var id: LocalizedStringKey {
        switch self {
        case let .feature(d): d.title
        case let .view(v): v.title
        }
    }
}

private struct Description {
    let icon: String?
    let title: LocalizedStringKey
    let description: LocalizedStringKey?
    var subfeatures: [(icon: String, description: LocalizedStringKey)] = []
}

private struct FeatureView {
    let icon: String?
    let title: LocalizedStringKey
    let view: () -> any View
}

let isInUS = false

private let versionDescriptions: [VersionDescription] = [
    VersionDescription(
        version: "v0.2",
        post: URL(string: "https://github.com/simpl-hq/zero/blob/main/CHANGELOG.md"),
        features: [
            .feature(Description(
                icon: "checkmark.shield",
                title: "SMP protocol & SQLCipher",
                description: "Unidirectional pairwise queues, 16 KB packet padding, and encrypted local storage."
            )),
            .feature(Description(
                icon: "checkmark",
                title: "Auto-accept contact requests",
                description: "Optional welcome messages and single-use invitation links."
            )),
        ]
    ),
    VersionDescription(
        version: "v0.3",
        post: URL(string: "https://github.com/simpl-hq/zero/blob/main/CHANGELOG.md"),
        features: [
            .feature(Description(
                icon: "person.2",
                title: "Secret groups",
                description: "Pairwise encrypted groups with join links and delivery receipts."
            )),
            .feature(Description(
                icon: "mic",
                title: "Voice messages",
                description: "Encrypted voice clips and irreversible message deletion."
            )),
            .feature(Description(
                icon: "eye.slash",
                title: "Local privacy lock",
                description: "Hide app previews in recent apps and require Face ID / passcode."
            )),
        ]
    ),
    VersionDescription(
        version: "v0.4",
        post: URL(string: "https://github.com/simpl-hq/zero/blob/main/CHANGELOG.md"),
        features: [
            .feature(Description(
                icon: "arrow.up.doc",
                title: "XFTP encrypted files",
                description: "Chunked encrypted uploads and downloads with SHA-512 verification."
            )),
            .feature(Description(
                icon: "stopwatch",
                title: "Disappearing & live messages",
                description: "Per-chat message timers, quote replies, reactions, and edits."
            )),
            .feature(Description(
                icon: "desktopcomputer",
                title: "Remote device control",
                description: "Pair mobile accounts securely with desktop clients."
            )),
        ]
    ),
    VersionDescription(
        version: "v0.5",
        post: URL(string: "https://github.com/simpl-hq/zero/blob/main/CHANGELOG.md"),
        features: [
            .feature(Description(
                icon: "key",
                title: "Post-quantum hybrid ratchet",
                description: "sntrup761 + X448 key encapsulation on every forward-secret ratchet step."
            )),
            .feature(Description(
                icon: "arrow.forward",
                title: "2-hop onion routing",
                description: "Protect your IP address from recipient messaging relays."
            )),
            .feature(Description(
                icon: "network.badge.shield.half.filled",
                title: "SOCKS5 proxy isolation",
                description: "Per-profile Tor / SOCKS5 circuit isolation and SPKI TLS pinning."
            )),
        ]
    ),
    VersionDescription(
        version: "v0.6",
        post: URL(string: "https://github.com/simpl-hq/zero/blob/main/CHANGELOG.md"),
        features: [
            .feature(Description(
                icon: "phone.arrow.up.right",
                title: "Encrypted WebRTC calls",
                description: "Audio and video calls with picture-in-picture and TURN relay mode."
            )),
            .feature(Description(
                icon: "tray.and.arrow.up",
                title: "QR profile migration",
                description: "Transfer encrypted local media and chat history between devices."
            )),
            .feature(Description(
                icon: "battery.50",
                title: "Background optimization",
                description: "Lower idle wakeup overhead across Notification Service Extensions."
            )),
        ]
    ),
    VersionDescription(
        version: "v0.7",
        post: URL(string: "https://github.com/simpl-hq/zero/blob/main/CHANGELOG.md"),
        features: [
            .feature(Description(
                icon: "person.crop.rectangle.stack",
                title: "Multiple chat profiles",
                description: "Separate identities, passcodes, hidden profiles, and self-destruct wipe."
            )),
            .feature(Description(
                icon: "theatermasks",
                title: "Incognito & pre-join review",
                description: "Connect with random ephemeral profiles and chat with group admins before admission."
            )),
            .feature(Description(
                icon: "at",
                title: "Member mentions",
                description: "Highlight direct mentions inside groups."
            )),
        ]
    ),
    VersionDescription(
        version: "v0.8",
        post: URL(string: "https://github.com/simpl-hq/zero/blob/main/CHANGELOG.md"),
        features: [
            .feature(Description(
                icon: "list.bullet",
                title: "Chat lists & moderation",
                description: "Custom folders, unread filters, batch forwarding, and private reports."
            )),
            .feature(Description(
                icon: "network.badge.shield.half.filled",
                title: "Safe web links",
                description: "Opt-in previews with tracking removal and phishing protection."
            )),
            .feature(Description(
                icon: "checkmark.shield",
                title: "CommonCrypto CSPRNG",
                description: "Apple Security.framework SecRandomCopyBytes support in core crypto."
            )),
        ]
    ),
    VersionDescription(
        version: "v0.9",
        post: URL(string: "https://github.com/simpl-hq/zero/blob/main/CHANGELOG.md"),
        features: [
            .feature(Description(
                icon: "server.rack",
                title: "Channels & relay ownership",
                description: "Multi-relay broadcast channels with contributor/moderator roles and security code verification."
            )),
            .feature(Description(
                icon: "terminal",
                title: "SDK & bot runtimes",
                description: "Aligned Node.js, Python, and TypeScript client libraries plus directory bot."
            )),
        ]
    ),
    VersionDescription(
        version: "v1.0.0",
        post: URL(string: "https://github.com/simpl-hq/zero/blob/main/CHANGELOG.md"),
        features: [
            .feature(Description(
                icon: "link.badge.plus",
                title: "4-word & 6-digit discovery",
                description: "Out-of-band contact sharing with Argon2id (8 MiB) proof-of-work across mobile and desktop."
            )),
            .feature(Description(
                icon: "checkmark.shield",
                title: "Zero v1.0.0 release",
                description: "Cross-platform parity across iOS, Android, macOS, Windows, Linux, and CLI with multi-region relays."
            )),
            .view(FeatureView(
                icon: nil,
                title: "Short Zero address",
                view: { CreateUpdateAddressShortLink() }
            )),
        ]
    ),
]

private let lastVersion = versionDescriptions.last!.version

func setLastVersionDefault() {
    UserDefaults.standard.set(lastVersion, forKey: DEFAULT_WHATS_NEW_VERSION)
}

func shouldShowWhatsNew() -> Bool {
    let v = UserDefaults.standard.string(forKey: DEFAULT_WHATS_NEW_VERSION)
    setLastVersionDefault()
    return v != lastVersion
}

fileprivate struct NewOperatorsView: View {
    var body: some View {
        VStack(alignment: .leading) {
            Image((operatorsInfo[.flux] ?? ServerOperator.dummyOperatorInfo).largeLogo)
                .resizable()
                .scaledToFit()
                .frame(height: 48)
            Text("The second preset operator in the app!")
                .multilineTextAlignment(.leading)
                .lineLimit(10)
            HStack {
                Text("Enable Flux in Network & servers settings for better metadata privacy.")
            }
        }
    }
}

fileprivate struct CreateUpdateAddressShortLink: View {
    @EnvironmentObject private var chatModel: ChatModel
    @EnvironmentObject var theme: AppTheme
    @State private var showAddressSheet = false
    @State private var progressIndicator = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 4) {
                Image(systemName: "link")
                    .symbolRenderingMode(.monochrome)
                    .foregroundColor(theme.colors.secondary)
                    .frame(minWidth: 30, alignment: .center)
                Text("Short Zero address").font(.title3).bold()
            }
            Group {
                if let addr = chatModel.userAddress {
                    if addr.shouldBeUpgraded {
                        HStack(spacing: 8) {
                            Button("Upgrade your address") { upgradeAndShareAddressAlert(progressIndicator: $progressIndicator) }
                            if progressIndicator {
                                ProgressView()
                            }
                        }
                    } else {
                        Button("Share your address") { addr.shareAddress(short: true) }
                    }
                } else {
                    Button("Create your address") { showAddressSheet = true }
                }
            }
            .multilineTextAlignment(.leading)
            .lineLimit(10)
        }
        .sheet(isPresented: $showAddressSheet) {
            NavigationView {
                UserAddressView(autoCreate: true)
                    .navigationTitle("Zero address")
                    .navigationBarTitleDisplayMode(.large)
                    .modifier(ThemedBackground(grouped: true))
            }
        }
    }
}

fileprivate struct InvestInZero: View {
    @EnvironmentObject var theme: AppTheme
    @State private var showGetStakeSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Support Zero").font(.title3).bold()
            (Text("Open-source privacy software under Simpl.") + Text(verbatim: " ") + Text("Learn more").foregroundColor(theme.colors.primary))
                .multilineTextAlignment(.leading)
                .onTapGesture { showGetStakeSheet = true }
            #if ZERO_ASSETS
            Image("crowdfunding_1")
                .resizable()
                .scaledToFit()
                .cornerRadius(12)
                .padding(.vertical, 4)
                .onTapGesture { showGetStakeSheet = true }
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showGetStakeSheet) {
            GetStakeView(fromSettings: false, showFirstImage: false)
        }
    }
}

fileprivate let getStakeSlides: [(image: String, heading: String, info: String?, text: String)] = [
    (
        "crowdfunding_1",
        "Zero-identifier private messaging",
        nil,
        "Zero removes phone numbers, usernames, and server-side social graphs so communication stays private by math rather than policy."
    ),
    (
        "crowdfunding_2",
        "Post-quantum and open source",
        nil,
        "Every component—from Curve448 + sntrup761 transport to the Argon2id contact-code broker—is auditable under AGPL-3.0."
    ),
    (
        "crowdfunding_3",
        "Independent relay infrastructure",
        "Relays store no user accounts and retain no plaintext history.",
        "Community donations directly cover relay bandwidth, TURN media servers, and continuous engineering."
    ),
    (
        "crowdfunding_4",
        "No ads, no trackers, no telemetry",
        "Zero remains free to use across iOS, Android, macOS, Windows, Linux, and CLI.",
        "Support development directly at simpl.global/donate."
    ),
]

private let donateURL = URL(string: "https://simpl.global/donate")!

private let zeroSupportURL = URL(string: "https://simpl.global/donate")!

struct GetStakeView: View {
    @Environment(\.dismiss) var dismiss: DismissAction
    @EnvironmentObject var chatModel: ChatModel
    var fromSettings: Bool
    var showFirstImage: Bool

    var body: some View {
        ZoomablePageView {
            VStack(alignment: .leading, spacing: 18) {
                Text(verbatim: "Support\nZero")
                    .font(.largeTitle)
                    .bold()
                    .fixedSize(horizontal: false, vertical: true)
                    .if(!fromSettings) { $0.padding(.top) }
                if showFirstImage {
                    slideImage(getStakeSlides[0])
                }
                (Text(verbatim: getStakeSlides[0].text) + Text(verbatim: " Donate via simpl.global/donate.").bold().foregroundColor(.accentColor))
                    .multilineTextAlignment(.leading)
                    .onTapGesture {
                        UIApplication.shared.open(donateURL)
                    }
                .padding(.bottom)
                ForEach(getStakeSlides[1...3], id: \.image) { slide in
                    VStack(alignment: .leading) {
                        slideImage(slide)
                        Text(slide.text)
                    }
                    .padding(.bottom)
                }

                Button {
                    UIApplication.shared.open(donateURL)
                } label: {
                    Text(verbatim: "Support on simpl.global")
                }
                .buttonStyle(OnboardingButtonStyle())

                Button {
                    dismiss()
                    DispatchQueue.main.async {
                        ChatModel.shared.appOpenUrl = zeroSupportURL
                    }
                } label: {
                    Text(verbatim: "Visit simpl.global")
                        .font(.callout)
                }
                .disabled(chatModel.chatRunning != true)
                .frame(maxWidth: .infinity)
            }
            .padding()
        }
        .ignoresSafeArea(edges: .bottom)
        .modifier(ThemedBackground(grouped: true))
    }

    @ViewBuilder
    func slideImage(_ slide: (image: String, heading: String, info: String?, text: String?)) -> some View {
        #if ZERO_ASSETS
        Image(slide.image)
            .resizable()
            .scaledToFit()
            .cornerRadius(12)
        #else
        Text(slide.heading).font(.title3).bold()
        if let info = slide.info {
            Text(info)
        }
        #endif
    }
}

private enum WhatsNewViewSheet: Identifiable {
    case showConditions

    var id: String {
        switch self {
        case .showConditions: return "showConditions"
        }
    }
}

struct WhatsNewView: View {
    @Environment(\.dismiss) var dismiss: DismissAction
    @EnvironmentObject var theme: AppTheme
    @State var currentVersion = versionDescriptions.count - 1
    @State var currentVersionNav = versionDescriptions.count - 1
    var viaSettings = false
    var updatedConditions: Bool
    @State private var sheetItem: WhatsNewViewSheet? = nil

    var body: some View {
        whatsNewView()
            .sheet(item: $sheetItem) { item in
                switch item {
                case .showConditions:
                    UsageConditionsView(
                        currUserServers: Binding.constant([]),
                        userServers: Binding.constant([])
                    )
                    .modifier(ThemedBackground(grouped: true))
                }
            }
    }

    private func whatsNewView() -> some View {
        VStack {
            TabView(selection: $currentVersion) {
                ForEach(Array(versionDescriptions.enumerated()), id: \.0) { (i, v) in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("New in \(v.version)")
                                .font(.title)
                                .foregroundColor(theme.colors.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical)
                            ForEach(v.features) { f in
                                switch f {
                                case let .feature(d): featureDescription(d).padding(.bottom, 8)
                                case let .view(v): AnyView(v.view()).padding(.bottom, 8)
                                }
                            }
                            if let post = v.post {
                                ExternalLink(destination: post) {
                                    HStack {
                                        Text("Read more")
                                        Image(systemName: "arrow.up.right.circle")
                                    }
                                }
                            }
                            if updatedConditions {
                                Button("View updated conditions") {
                                    sheetItem = .showConditions
                                }
                            }
                            if !viaSettings {
                                Spacer()

                                Button("Ok") {
                                    dismiss()
                                }
                                .font(.title3)
                                .frame(maxWidth: .infinity, alignment: .center)

                                Spacer()
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            Spacer()
            pagination()
        }
        .padding()
        .onChange(of: currentVersion) { _ in
            currentVersionNav = currentVersion
        }
    }

    @ViewBuilder private func featureHeader(_ icon: String?, _ title: LocalizedStringKey) -> some View {
        if let icon {
            HStack(alignment: .center, spacing: 4) {
                Image(systemName: icon)
                    .symbolRenderingMode(.monochrome)
                    .foregroundColor(theme.colors.secondary)
                    .frame(minWidth: 30, alignment: .center)
                Text(title).font(.title3).bold()
            }
        } else {
            Text(title).font(.title3).bold()
        }
    }

    private func featureDescription(_ f: Description) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            featureHeader(f.icon, f.title)
            if let d = f.description {
                Text(d)
                    .multilineTextAlignment(.leading)
                    .lineLimit(10)
            }
            if f.subfeatures.count > 0 {
                ForEach(f.subfeatures, id: \.icon) { s in
                    HStack(alignment: .center, spacing: 4) {
                        Image(systemName: s.icon)
                            .symbolRenderingMode(.monochrome)
                            .foregroundColor(theme.colors.secondary)
                            .frame(minWidth: 30, alignment: .center)
                        Text(s.description)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                    }
                }
            }
        }
    }

    private func pagination() -> some View {
        HStack {
            if currentVersionNav > 0 {
                let prev = currentVersionNav - 1
                Button {
                    currentVersionNav = prev
                    withAnimation { currentVersion = prev }
                } label: {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text(versionDescriptions[prev].version)
                    }
                }
            }
            Spacer()
            if currentVersionNav < versionDescriptions.count - 1 {
                let next = currentVersionNav + 1
                Button {
                    currentVersionNav = next
                    withAnimation { currentVersion = next }
                } label: {
                    HStack {
                        Text(versionDescriptions[next].version)
                        Image(systemName: "chevron.right")
                    }
                }
            }
        }
    }
}

struct NewFeaturesView_Previews: PreviewProvider {
    static var previews: some View {
        WhatsNewView(updatedConditions: false)
    }
}
