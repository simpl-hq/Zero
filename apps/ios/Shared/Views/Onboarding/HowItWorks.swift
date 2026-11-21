import SwiftUI
import UIKit
import Zero

// step model for guided setup tutorial
private struct GuidedTutorialStep {
    let icon: String
    let eyebrow: String
    let title: String
    let summary: String
    let highlights: [(icon: String, heading: String, detail: String)]
}

// interactive guided setup and usage tutorial for simpl zero
struct ZeroGuidedTutorialView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var m: ChatModel
    @EnvironmentObject var theme: AppTheme

    var allowSettingsShortcuts: Bool = true
    var onComplete: (() -> Void)? = nil

    @State private var currentStep: Int = 0
    @State private var phrase: String = ZeroIdentityBridge.shared.currentPhrase ?? ""
    @State private var deepLink: String = ZeroIdentityBridge.shared.currentDeepLink ?? ""
    @State private var ephemeralCode: String? = nil
    @State private var statusBanner: String? = nil
    @State private var isGeneratingCode: Bool = false
    @State private var backedUpPhrase: Bool = false
    @State private var showHybridConnect: Bool = false
    @State private var showNetworkSettings: Bool = false
    @State private var showPrivacySettings: Bool = false
    @StateObject private var ss = SaveableSettings()

    private let steps: [GuidedTutorialStep] = [
        GuidedTutorialStep(
            icon: "key.fill",
            eyebrow: "STEP 1 · NO ACCOUNTS",
            title: "Your Zero Identity",
            summary: "Zero never uses phone numbers, emails, or server accounts. Everything lives encrypted locally on your device.",
            highlights: [
                ("key.fill", "4-Word Phrase", "Share your phrase or simpl.global/add link so friends can reach you without an account directory."),
                ("iphone", "One-Way Queues", "Contacts send only into isolated queues on your relay while your replies go to theirs.")
            ]
        ),
        GuidedTutorialStep(
            icon: "link.badge.plus",
            eyebrow: "STEP 2 · CONNECT",
            title: "Three Ways to Pair",
            summary: "Pick whichever handoff fits how you meet: remote links, fast verbal codes, or camera QR scans.",
            highlights: [
                ("number.circle.fill", "6-Digit Code (5 min)", "Generate a short code when standing next to someone or over voice."),
                ("qrcode.viewfinder", "1-Time Link & QR", "Create single-use links when sharing publicly so nobody else can reuse the invite.")
            ]
        ),
        GuidedTutorialStep(
            icon: "shield.lefthalf.filled",
            eyebrow: "STEP 3 · METADATA",
            title: "Private Routing & Media",
            summary: "Every message travels as a fixed 16 KB encrypted packet with Curve448 + sntrup761 post-quantum keys.",
            highlights: [
                ("arrow.triangle.branch", "2-Hop Onion Mode", "Hide your IP address from recipient relays via a forwarding hop in Network & servers."),
                ("doc.fill", "XFTP Media Transfers", "Images, voice clips, and files upload encrypted in chunks and auto-expire off relays.")
            ]
        ),
        GuidedTutorialStep(
            icon: "faceid",
            eyebrow: "STEP 4 · SOVEREIGNTY",
            title: "Lock Your Device",
            summary: "Because Zero servers keep no message history, securing the phone or desktop in your hand protects everything.",
            highlights: [
                ("lock.shield.fill", "Face ID & Screen Blur", "Enable biometric app lock and blur previews in Recent Apps under Privacy."),
                ("externaldrive.badge.checkmark", "Passphrase & Backups", "Back up your local archive before switching phones or wiping device storage.")
            ]
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            tutorialHeader
            progressBar

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    stepHeroCard(steps[currentStep])
                    stepInteractiveSection(for: currentStep)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }

            footerNavigation
        }
        .background(theme.colors.background.ignoresSafeArea())
        .onAppear { ensureIdentityLoaded() }
        .sheet(isPresented: $showHybridConnect) {
            ZeroHybridConnectSheet()
                .environmentObject(m)
                .environmentObject(theme)
        }
        .sheet(isPresented: $showNetworkSettings) {
            NavigationView {
                NetworkAndServers()
                    .navigationBarTitle("", displayMode: .inline)
                    .modifier(ThemedBackground(grouped: true))
                    .environmentObject(m)
                    .environmentObject(theme)
                    .environmentObject(ss)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showNetworkSettings = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showPrivacySettings) {
            NavigationView {
                PrivacySettings()
                    .navigationBarTitle("", displayMode: .inline)
                    .modifier(ThemedBackground(grouped: true))
                    .environmentObject(m)
                    .environmentObject(theme)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showPrivacySettings = false }
                        }
                    }
            }
        }
    }

    private var tutorialHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Setup & Quick Guide")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(theme.colors.onBackground)
                Text("Step \(currentStep + 1) of \(steps.count)")
                    .font(.caption)
                    .foregroundColor(theme.colors.secondary)
            }
            Spacer()
            Button(onComplete != nil ? "Skip" : "Done") {
                finishTutorial()
            }
            .font(.subheadline.weight(.medium))
            .foregroundColor(theme.colors.primary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(0..<steps.count, id: \.self) { index in
                Capsule()
                    .fill(index <= currentStep ? theme.colors.primary : theme.colors.secondary.opacity(0.22))
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .animation(.easeInOut(duration: 0.2), value: currentStep)
    }

    private func stepHeroCard(_ step: GuidedTutorialStep) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: step.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(theme.colors.primary)
                    .frame(width: 44, height: 44)
                    .background(theme.colors.primary.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(step.eyebrow)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(theme.colors.secondary)
                    Text(step.title)
                        .font(.title3.weight(.bold))
                        .foregroundColor(theme.colors.onBackground)
                }
            }

            Text(step.summary)
                .font(.subheadline)
                .foregroundColor(theme.colors.onBackground.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                ForEach(Array(step.highlights.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.icon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(theme.colors.primary)
                            .frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.heading)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(theme.colors.onBackground)
                            Text(item.detail)
                                .font(.caption)
                                .foregroundColor(theme.colors.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(theme.colors.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private func stepInteractiveSection(for step: Int) -> some View {
        switch step {
        case 0:
            identityCard
        case 1:
            connectActionsCard
        case 2:
            if allowSettingsShortcuts {
                actionButtonRow(
                    icon: "network",
                    title: "Open Network & Servers",
                    subtitle: "Review relay routing & 2-hop onion privacy"
                ) {
                    showNetworkSettings = true
                }
            }
        default:
            securityChecklistCard
        }
    }

    private var identityCard: some View {
        let displayPhrase = phrase.isEmpty ? "Provisioning phrase..." : phrase
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(statusBanner ?? "YOUR ACTIVE 4-WORD PHRASE")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(statusBanner != nil ? theme.colors.primary : theme.colors.secondary)
                Spacer()
                Button {
                    guard !phrase.isEmpty else { return }
                    UIPasteboard.general.string = phrase
                    showStatus("4-Word Phrase Copied")
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(theme.colors.primary)
                }
                .disabled(phrase.isEmpty)
            }

            Text(displayPhrase)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(theme.colors.onBackground)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !deepLink.isEmpty {
                Button {
                    UIPasteboard.general.string = deepLink
                    showStatus("Invite Link Copied")
                } label: {
                    Text(deepLink)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(theme.colors.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var connectActionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(statusBanner ?? "TRY PAIRING TOOLS")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(statusBanner != nil ? theme.colors.primary : theme.colors.secondary)

            if let ephemeralCode {
                HStack {
                    Text("Live 5-min Code:")
                        .font(.caption)
                        .foregroundColor(theme.colors.secondary)
                    Text(ephemeralCode)
                        .font(.system(.headline, design: .monospaced).weight(.bold))
                        .foregroundColor(theme.colors.primary)
                    Spacer()
                    Button("Copy") {
                        UIPasteboard.general.string = ephemeralCode
                        showStatus("6-Digit Code Copied")
                    }
                    .font(.caption.weight(.semibold))
                }
                .padding(10)
                .background(theme.colors.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack(spacing: 10) {
                Button {
                    generateCode()
                } label: {
                    HStack(spacing: 6) {
                        if isGeneratingCode {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "number.circle")
                        }
                        Text("6-Digit Code")
                            .lineLimit(1)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(theme.colors.onBackground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(theme.colors.secondary.opacity(0.35), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isGeneratingCode)

                if allowSettingsShortcuts {
                    Button {
                        showHybridConnect = true
                    } label: {
                        Label("Connect Now", systemImage: "person.badge.plus")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(theme.colors.onPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(theme.colors.primary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var securityChecklistCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation { backedUpPhrase.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: backedUpPhrase ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(backedUpPhrase ? theme.colors.primary : theme.colors.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("I saved my 4-word phrase safely")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(theme.colors.onBackground)
                        Text("You can also inspect it later under Settings -> About Zero.")
                            .font(.caption)
                            .foregroundColor(theme.colors.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if allowSettingsShortcuts {
                actionButtonRow(
                    icon: "faceid",
                    title: "Open Privacy & Face ID Lock",
                    subtitle: "Configure biometric unlock and screen blur"
                ) {
                    showPrivacySettings = true
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func actionButtonRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundColor(theme.colors.primary)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(theme.colors.onBackground)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(theme.colors.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(theme.colors.secondary)
            }
            .padding(14)
            .background(theme.colors.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var footerNavigation: some View {
        HStack(spacing: 12) {
            if currentStep > 0 {
                Button {
                    withAnimation { currentStep -= 1 }
                } label: {
                    Text("Back")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(theme.colors.onBackground)
                        .frame(width: 96, height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(theme.colors.secondary.opacity(0.35), lineWidth: 1.2)
                        )
                }
                .buttonStyle(.plain)
            }

            Button {
                if currentStep < steps.count - 1 {
                    withAnimation { currentStep += 1 }
                } else {
                    finishTutorial()
                }
            } label: {
                Text(currentStep < steps.count - 1 ? "Next Step" : (onComplete != nil ? "Start Using Zero" : "Done"))
                    .font(.headline)
                    .foregroundColor(theme.colors.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(theme.colors.primary, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(theme.colors.background)
    }

    private func ensureIdentityLoaded() {
        if let existing = ZeroIdentityBridge.shared.currentPhrase, ZeroIdentityBridge.isValid4WordPhrase(existing) {
            phrase = existing
            if deepLink.isEmpty {
                deepLink = ZeroIdentityBridge.shared.currentDeepLink
                    ?? "\(ZeroIdentityBridge.deepLinkPrefix)\(existing.lowercased().replacingOccurrences(of: "-", with: ""))"
            }
            return
        }
        Task {
            let invite = m.userAddress?.connLinkContact.connFullLink ?? ""
            if let provisioned = try? await ZeroIdentityBridge.shared.provisionPhraseAndDeepLink(localCryptoInviteUrl: invite) {
                await MainActor.run {
                    phrase = provisioned.phrase
                    deepLink = provisioned.deepLink
                }
            }
        }
    }

    private func generateCode() {
        isGeneratingCode = true
        Task {
            let invite = m.userAddress?.connLinkContact.connFullLink ?? ""
            let code = try? await ZeroIdentityBridge.shared.provisionEphemeral6DigitCode(localCryptoInviteUrl: invite)
            await MainActor.run {
                isGeneratingCode = false
                if let code, !code.isEmpty {
                    ephemeralCode = code
                } else {
                    showStatus("Connect to network to mint 6-digit code")
                }
            }
        }
    }

    private func showStatus(_ msg: String) {
        statusBanner = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if statusBanner == msg {
                statusBanner = nil
            }
        }
    }

    private func finishTutorial() {
        if let onComplete {
            onComplete()
        } else {
            dismiss()
        }
    }
}

struct OldHowItWorks: View {
    @Environment(\.dismiss) var dismiss: DismissAction
    @EnvironmentObject var m: ChatModel
    var onboarding: Bool
    @Binding var createProfileNavLinkActive: Bool

    var body: some View {
        VStack(alignment: .leading) {
            Text("How Zero works")
                .font(.largeTitle)
                .bold()
                .padding(.vertical)
            ScrollView {
                VStack(alignment: .leading) {
                    Group {
                        Text("To protect your privacy, Zero uses separate IDs for each of your contacts.")
                        Text("Only client devices store user profiles, contacts, groups, and messages.")
                        Text("All messages and files are sent **end-to-end encrypted**, with post-quantum security in direct messages.")
                        if !onboarding {
                            ExternalLink("Read more in our GitHub repository.", destination: URL(string: "https://github.com/simpl-hq/zero#readme")!)
                        }
                    }
                    .padding(.bottom)
                }
            }

            Spacer()

            if onboarding {
                VStack(spacing: 10) {
                    createFirstProfileButton()
                    onboardingButtonPlaceholder()
                }
            }
        }
        .lineLimit(10)
        .padding(onboarding ? 25 : 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .modifier(ThemedBackground())
    }

    private func createFirstProfileButton() -> some View {
        Button {
            dismiss()
            createProfileNavLinkActive = true
        } label: {
            Text("Create your profile")
        }
        .buttonStyle(OnboardingButtonStyle(isDisabled: false))
    }
}

struct WhyZero: View {
    @Environment(\.dismiss) var dismiss: DismissAction
    @EnvironmentObject var m: ChatModel
    var onboarding: Bool
    @Binding var createProfileNavLinkActive: Bool

    var body: some View {
        VStack(alignment: .leading) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("You were born without an account")
                        .font(.title)
                        .bold()
                        .padding(.top)
                    Text("Nobody tracked your conversations. No one drew a map of where you'd been. Privacy was never a feature - it was the way of life.")
                    Text("Then we moved online, and every platform asked for a piece of you - your name, your number, your friends. We accepted that the price of talking to others is letting someone know who we talk to. Every generation, people and tech, had it this way - telephone, email, messengers, social media. It seemed the only way possible.")
                    Text("There is another way. A network with no phone numbers. No usernames. No accounts. No user identities of any kind. A network that connects people and carries encrypted messages without knowing who is connected.")
                    Text("Not a better lock on someone else's door. Not a nicer landlord that respects your privacy, but still keeps the record of all visitors. You are not a guest. You are home. No king can enter it - you are sovereign.")
                    Text("Your conversations belong to you, as it had always been before the Internet. The network is not a place you visit. It is a place you create and own. And nobody can take it from you, whether you make it private or public.")
                    Text("The oldest human freedom - to speak to another person without being watched - built on infrastructure that cannot betray it.")
                    Text("Because we destroyed the power to know who you are. So that your power can never be taken.")
                    Text("Be free in your network.")
                }
            }
            .padding(.bottom, 16)

            Spacer()

            if onboarding {
                createFirstProfileButton()
            }
        }
        .padding(onboarding ? 25 : 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .modifier(ThemedBackground())
    }

    private func createFirstProfileButton() -> some View {
        Button {
            dismiss()
            createProfileNavLinkActive = true
        } label: {
            Text("Get started")
        }
        .buttonStyle(OnboardingButtonStyle(isDisabled: false))
    }
}

struct WhyZero_Previews: PreviewProvider {
    static var previews: some View {
        ZeroGuidedTutorialView()
    }
}
