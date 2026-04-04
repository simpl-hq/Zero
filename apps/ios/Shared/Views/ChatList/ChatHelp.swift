import SwiftUI

struct ChatHelp: View {
    @EnvironmentObject var chatModel: ChatModel
    @EnvironmentObject var theme: AppTheme
    @State private var showNewChatSheet = false
    @State private var showGuidedTutorial = false
    let dismissSettingsSheet: DismissAction

    var body: some View {
        ScrollView { chatHelp() }
            .sheet(isPresented: $showGuidedTutorial) {
                ZeroGuidedTutorialView(allowSettingsShortcuts: true) {
                    showGuidedTutorial = false
                }
                .environmentObject(chatModel)
                .environmentObject(theme)
            }
    }

    func chatHelp() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Thank you for installing Zero!")

            Button {
                showGuidedTutorial = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open Guided Setup Tutorial")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                        Text("4 interactive steps: phrase, pairing codes, onion routing & Face ID")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.86))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(theme.colors.primary)
                )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Text("Quick overview")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("**Your 4-Word Phrase**: Zero needs no email or phone number. Share your 4-word phrase or `simpl.global/add` link when someone wants to message you.")
                Text("**6-Digit In-Person Code**: Mint a 5-minute code from the home card or `+` menu when connecting side by side or over a call.")
                Text("**2-Hop Private Routing**: Turn on Private routing under Network & servers so your IP address stays hidden from a contact's relay.")
                Text("**Local Device Security**: Messages live encrypted only on this device. Enable Face ID lock in Your privacy and back up your phrase.")
            }
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 0) {
                Text("To ask any questions or follow project updates:")
                ExternalLink("open GitHub Issues / Simpl.", destination: URL(string: "https://github.com/simpl-hq/zero/issues")!)
                    .padding(.top, 2)
            }
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 10) {
                Text("To make a new connection")
                    .font(.title2)
                    .fontWeight(.bold)

                HStack(spacing: 8) {
                    Text("Tap button ")
                    NewChatMenuButton(showNewChatSheet: $showNewChatSheet)
                    Text("above, then choose:")
                }

                Text("**Create 1-time link**: to create and share a new invitation link.")
                Text("**Scan / Paste link**: to connect via a link you received.")
                Text("**Create group**: to create a new group.")
            }
            .padding(.top, 16)

            VStack(alignment: .leading, spacing: 10) {
                Text("Markdown in messages")
                    .font(.title2)
                    .fontWeight(.bold)

                MarkdownHelp()
            }
            .padding(.top, 16)
        }
        .padding()
    }
}

struct ChatHelp_Previews: PreviewProvider {
    @Environment(\.dismiss) static var mockDismiss

    static var previews: some View {
        ChatHelp(dismissSettingsSheet: mockDismiss)
    }
}
