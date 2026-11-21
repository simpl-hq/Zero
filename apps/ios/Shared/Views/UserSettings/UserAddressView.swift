import SwiftUI
import MessageUI
@preconcurrency import Zero

struct UserAddressView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss: DismissAction
    @EnvironmentObject private var chatModel: ChatModel
    @EnvironmentObject var theme: AppTheme
    @State var shareViaProfile = false
    @State var autoCreate = false
    var onboarding: Bool = false
    @State private var showShortLink = true
    @State private var settings = AddressSettingsState()
    @State private var savedSettings = AddressSettingsState()
    @State private var showMailView = false
    @State private var mailViewResult: Result<MFMailComposeResult, Error>? = nil
    @State private var alert: UserAddressAlert?
    @State private var progressIndicator = false
    @State private var showShareViaChat = false

    private enum UserAddressAlert: Identifiable {
        case deleteAddress
        case shareOnCreate
        case error(title: LocalizedStringKey, error: LocalizedStringKey?)

        var id: String {
            switch self {
            case .deleteAddress: return "deleteAddress"
            case .shareOnCreate: return "shareOnCreate"
            case let .error(title, _): return "error \(title)"
            }
        }
    }

    var body: some View {
        ZStack {
            userAddressView()

            if progressIndicator {
                ZStack {
                    if chatModel.userAddress != nil {
                        Circle()
                            .fill(.white)
                            .opacity(0.7)
                            .frame(width: 56, height: 56)
                    }
                    ProgressView().scaleEffect(2)
                }
            }
        }
        .if(onboarding) { v in
            v.toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Image(systemName: "info.circle").opacity(0)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            if chatModel.userAddress == nil, autoCreate {
                createAddress()
            }
        }
    }

    private func userAddressView() -> some View {
        List {
            if let userAddress = chatModel.userAddress {
                if onboarding {
                    onboardingAddressView(userAddress)
                } else {
                    existingAddressView(userAddress)
                        .onAppear {
                            settings = AddressSettingsState(settings: userAddress.addressSettings)
                            savedSettings = AddressSettingsState(settings: userAddress.addressSettings)
                        }
                }
            } else if !onboarding {
                Section {
                    createAddressButton()
                }

                Section {
                    createOneTimeLinkButton()
                } header: {
                    Text("Or to share privately")
                        .foregroundColor(theme.colors.secondary)
                }

                Section {
                    learnMoreButton()
                }
            }
        }
        .alert(item: $alert) { alert in
            switch alert {
            case .deleteAddress:
                return Alert(
                    title: Text("Delete address?"),
                    message: Text("All your contacts will remain connected."),
                    primaryButton: .destructive(Text("Delete")) {
                        progressIndicator = true
                        Task {
                            do {
                                if let u = try await apiDeleteUserAddress() {
                                    DispatchQueue.main.async {
                                        chatModel.userAddress = nil
                                        chatModel.updateUser(u)
                                        if shareViaProfile {
                                            shareViaProfile = false
                                        }
                                    }
                                }
                                await MainActor.run { progressIndicator = false }
                            } catch let error {
                                logger.error("UserAddressView apiDeleteUserAddress: \(responseError(error))")
                                await MainActor.run { progressIndicator = false }
                            }
                        }
                    }, secondaryButton: .cancel()
                )
            case .shareOnCreate:
                return Alert(
                    title: Text("Share address with Zero contacts?"),
                    message: Text("Add address to your profile."),
                    primaryButton: .default(Text("Share")) {
                        setProfileAddress($progressIndicator, true)
                        shareViaProfile = true
                    }, secondaryButton: .cancel()
                )
            case let .error(title, error):
                return mkAlert(title: title, message: error)
            }
        }
    }

    @ViewBuilder private func existingAddressView(_ userAddress: UserContactLink) -> some View {
        Section {
            ZeroCreatedLinkQRCode(link: userAddress.connLinkContact, short: $showShortLink)
                .id("zero-contact-address-qrcode-\(userAddress.connLinkContact.zeroChatUri(short: showShortLink))")
            if userAddress.shouldBeUpgraded {
                upgradeAddressButton()
            }
            shareAddressButton(userAddress)
            shareViaChatButton(userAddress)
            addressSettingsButton(userAddress)
        } header: {
            ToggleShortLinkHeader(text: Text(""), link: userAddress.connLinkContact, short: $showShortLink)
        }

        Section {
            NavigationLink {
                let zeroName = if let d = chatModel.currentUser?.profile.contactDomain?.domain { "@\(d)" } else { "" }
                SetZeroDomainView(
                    title: "Your Zero name",
                    footer: "Let people connect to you via name registered with your Zero address.",
                    prompt: "@yourname.testing",
                    zeroName: zeroName,
                    broadcastWarning: nil,
                    save: { zeroDomain in
                        do {
                            let u = try await apiSetUserDomain(zeroDomain)
                            await MainActor.run { chatModel.updateUser(u) }
                            return true
                        } catch {
                            return false
                        }
                    }
                )
            } label: {
                if let d = chatModel.currentUser?.profile.contactDomain?.domain {
                    Label("\(d)", systemImage: "at")
                } else {
                    Label("Zero Name (Coming Soon)", systemImage: "at")
                }
            }
        } header: {
            if chatModel.currentUser?.profile.contactDomain?.domain != nil {
                Text("Your Zero name").foregroundColor(theme.colors.secondary)
            }
        }

        Section {
            createOneTimeLinkButton()
        } header: {
            Text("Or to share privately")
                .foregroundColor(theme.colors.secondary)
        }

        Section {
            learnMoreButton()
        }

        Section {
            deleteAddressButton()
        } footer: {
            Text("Your contacts will remain connected.")
                .foregroundColor(theme.colors.secondary)
        }
    }

    @ViewBuilder private func onboardingAddressView(_ userAddress: UserContactLink) -> some View {
        Section {
            HStack(spacing: 8) {
                let link = userAddress.connLinkContact.zeroChatUri(short: showShortLink)
                linkTextView(link)
                Button { showShareSheet(items: [link]) } label: {
                    Image(systemName: "square.and.arrow.up")
                        .padding(.top, -7)
                        .padding(.horizontal, 8)
                }
            }
            .frame(maxWidth: .infinity)
        } header: {
            #if ZERO_ASSETS
            VStack(alignment: .leading) {
                Image(colorScheme == .light ? "zero-address" : "zero-address-light")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                Text("Use this address in your social media profile, website, or email signature.")
                    .font(.body).foregroundColor(theme.colors.onBackground).textCase(nil)
            }
            .padding(.bottom, 4)
            #else
            Text("Use this address in your social media profile, website, or email signature.")
                .font(.body).foregroundColor(theme.colors.onBackground).textCase(nil)
                .padding(.bottom, 6)
            #endif
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 10))

        Section {
            ZeroCreatedLinkQRCode(link: userAddress.connLinkContact, short: $showShortLink)
                .id("zero-contact-address-qrcode-\(userAddress.connLinkContact.zeroChatUri(short: showShortLink))")
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
                .padding(.horizontal)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        } header: {
            Text("Or use this QR - print or show online.").font(.body).foregroundColor(theme.colors.onBackground).textCase(nil)
        }
    }

    private func createAddressButton() -> some View {
        Button {
            createAddress()
        } label: {
            Label("Create Zero address", systemImage: "qrcode")
        }
    }

    private func createAddress() {
        progressIndicator = true
        Task {
            do {
                let connLinkContact = try await apiCreateUserAddress()
                DispatchQueue.main.async {
                    if let connLinkContact {
                        chatModel.userAddress = UserContactLink(connLinkContact)
                        let hasRelevantContacts = chatModel.chats.contains { chat in
                            if case let .direct(contact) = chat.chatInfo {
                                return contact.active && !contact.isContactCard && !contact.contactConnIncognito
                            }
                            return false
                        }
                        if hasRelevantContacts {
                            alert = .shareOnCreate
                            progressIndicator = false
                        } else {
                            setProfileAddress($progressIndicator, true)
                            shareViaProfile = true
                        }
                    } else {
                        progressIndicator = false
                    }
                }
            } catch let error {
                logger.error("UserAddressView apiCreateUserAddress: \(responseError(error))")
                await MainActor.run {
                    progressIndicator = false
                    showErrorAlert(error, NSLocalizedString("Error creating address", comment: ""))
                }
            }
        }
    }

    private func upgradeAddressButton() -> some View {
        Button {
            upgradeAndShareAddressAlert(progressIndicator: $progressIndicator)
        } label: {
            settingsRow("arrow.up", color: theme.colors.primary) {
                Text("Upgrade address")
            }
        }
    }

    private func createOneTimeLinkButton() -> some View {
        NavigationLink {
            NewChatView(selection: .invite)
                .navigationBarTitle("", displayMode: .inline)
                .navigationBarTitleDisplayMode(.inline)
                .modifier(ThemedBackground(grouped: true))
        } label: {
            Label("Create 1-time link", systemImage: "link.badge.plus")
                .foregroundColor(theme.colors.primary)
        }
    }

    private func deleteAddressButton() -> some View {
        Button(role: .destructive) {
            alert = .deleteAddress
        } label: {
            Label("Delete address", systemImage: "trash")
                .foregroundColor(Color.red)
        }
    }

    private func shareAddressButton(_ userAddress: UserContactLink) -> some View {
        return Button {
            if userAddress.shouldBeUpgraded {
                upgradeAndShareAddressAlert(progressIndicator: $progressIndicator, shareAddress: { userAddress.shareAddress(short: showShortLink) })
            } else {
                userAddress.shareAddress(short: showShortLink)
            }
        } label: {
            settingsRow("square.and.arrow.up", color: theme.colors.secondary) {
                Text("Share address")
            }
        }
    }

    private func shareViaChatButton(_ userAddress: UserContactLink) -> some View {
        Button {
            if userAddress.shouldBeUpgraded {
                showAlert(
                    NSLocalizedString("Upgrade address?", comment: "alert title"),
                    message: NSLocalizedString("The address will be short, and your profile will be shared via the address.", comment: "alert message"),
                    actions: {[
                        UIAlertAction(title: NSLocalizedString("Upgrade", comment: "alert button"), style: .default) { _ in
                            addShortLink(progressIndicator: $progressIndicator, onComplete: { showShareViaChat = true })
                        },
                        cancelAlertAction
                    ]}
                )
            } else {
                showShareViaChat = true
            }
        } label: {
            settingsRow("arrowshape.turn.up.forward", color: theme.colors.primary) {
                Text("Share via chat").foregroundColor(theme.colors.primary)
            }
        }
        .sheet(isPresented: $showShareViaChat) {
            shareAddressPicker()
        }
    }

    private func shareViaEmailButton(_ userAddress: UserContactLink) -> some View {
        Button {
            showMailView = true
        } label: {
            settingsRow("envelope", color: theme.colors.secondary) {
                Text("Invite friends")
            }
        }
        .sheet(isPresented: $showMailView) {
            SendAddressMailView(
                showMailView: $showMailView,
                mailViewResult: $mailViewResult,
                userAddress: userAddress
            )
            .edgesIgnoringSafeArea(.bottom)
        }
        .onChange(of: mailViewResult == nil) { _ in
            if let r = mailViewResult {
                switch r {
                case .success: ()
                case let .failure(error):
                    logger.error("UserAddressView share via email: \(responseError(error))")
                    showErrorAlert(error, NSLocalizedString("Error sending email", comment: ""))
                }
                mailViewResult = nil
            }
        }
    }

    private func addressSettingsButton(_ userAddress: UserContactLink) -> some View {
        NavigationLink {
            UserAddressSettingsView(shareViaProfile: $shareViaProfile)
                .navigationBarTitle("", displayMode: .inline)
                .navigationBarTitleDisplayMode(.inline)
                .modifier(ThemedBackground(grouped: true))
        } label: {
            Text("Address settings")
        }
    }

    private func learnMoreButton() -> some View {
        NavigationLink {
            UserAddressLearnMore()
                .navigationBarTitle("", displayMode: .inline)
                .modifier(ThemedBackground(grouped: true))
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            settingsRow("info.circle", color: theme.colors.secondary) {
                Text("Zero address or 1-time link?")
            }
        }
    }
}

func upgradeAndShareAddressAlert(progressIndicator: Binding<Bool>, shareAddress: (() -> Void)? = nil) {
    showAlert(
        NSLocalizedString("Upgrade address?", comment: "alert message"),
        message: NSLocalizedString("The address will be short, and your profile will be shared via the address.", comment: "alert message"),
        actions: {
            var actions = [UIAlertAction(title: NSLocalizedString("Upgrade", comment: "alert button"), style: .default) { _ in
                addShortLink(progressIndicator: progressIndicator, shareOnCompletion: shareAddress != nil)
            }]
            if let shareAddress {
                actions.append(UIAlertAction(title: NSLocalizedString("Share old address", comment: "alert button"), style: .default) { _ in
                    shareAddress()
                })
            }
            actions.append(cancelAlertAction)
            return actions
        }
    )
}

@ViewBuilder
func shareAddressPicker(composeState: Binding<ComposeState>? = nil) -> some View {
    let v = ChatItemForwardingView(
        title: "Share address",
        isProhibited: { $0.prohibitedByPref(hasZeroLink: true, isMediaOrFileAttachment: false, isVoice: false) },
        onSelectChat: { chat in shareMyAddress(chat, composeState: composeState) },
        includeLocal: false
    )
    if #available(iOS 16.0, *) {
        v.presentationDetents([.fraction(0.8)])
    } else {
        v
    }
}

func shareMyAddress(_ destChat: Chat, composeState: Binding<ComposeState>? = nil) {
    let sendAsGroup = if let gInfo = destChat.chatInfo.groupInfo { gInfo.useRelays && gInfo.membership.memberRole >= .owner } else { false }
    Task {
        do {
            let mc = try await apiShareMyAddress(
                toChatType: destChat.chatInfo.chatType, toChatId: destChat.chatInfo.apiId,
                toScope: destChat.chatInfo.groupChatScope(), sendAsGroup: sendAsGroup
            )
            if case let .chat(_, chatLink, ownerSig) = mc {
                await MainActor.run {
                    dismissAllSheets {
                        let cs = ComposeState(preview: .chatLinkPreview(chatLink: chatLink, ownerSig: ownerSig))
                        if let composeState {
                            composeState.wrappedValue = cs
                        } else {
                            ChatModel.shared.draft = cs
                            ChatModel.shared.draftChatId = destChat.id
                        }
                        if destChat.id != ChatModel.shared.chatId {
                            ItemsModel.shared.loadOpenChat(destChat.id)
                        }
                    }
                }
            } else {
                logger.error("shareMyAddress: unexpected MsgContent: \(String(describing: mc))")
                await MainActor.run {
                    showAlert(NSLocalizedString("Error sharing address", comment: "alert title"), message: String(describing: mc))
                }
            }
        } catch {
            logger.error("shareMyAddress error: \(error.localizedDescription)")
            await MainActor.run {
                showAlert(NSLocalizedString("Error sharing address", comment: "alert title"), message: error.localizedDescription)
            }
        }
    }
}

private func addShortLink(progressIndicator: Binding<Bool>, shareOnCompletion: Bool = false, onComplete: (() -> Void)? = nil) {
    progressIndicator.wrappedValue = true
    Task {
        do {
            let userAddress = try await apiAddMyAddressShortLink()
            await MainActor.run {
                ChatModel.shared.userAddress = userAddress
                progressIndicator.wrappedValue = false
                if shareOnCompletion, let userAddress {
                    userAddress.shareAddress(short: true)
                }
                onComplete?()
            }
        } catch let error {
            logger.error("apiAddMyAddressShortLink: \(responseError(error))")
            showAlert("Error adding short link", message: responseError(error))
            await MainActor.run { progressIndicator.wrappedValue = false }
        }
    }
}

struct ToggleShortLinkHeader: View {
    @EnvironmentObject var theme: AppTheme
    @AppStorage(DEFAULT_DEVELOPER_TOOLS) private var developerTools = false
    let text: Text
    var link: CreatedConnLink
    @Binding var short: Bool

    var body: some View {
        if link.connShortLink == nil || !developerTools {
            text.foregroundColor(theme.colors.secondary)
        } else {
            HStack {
                text.foregroundColor(theme.colors.secondary)
                Spacer()
                Text(short ? "Full link" : "Short link")
                    .textCase(.none)
                    .foregroundColor(theme.colors.primary)
                    .onTapGesture { short.toggle() }
            }
        }
    }
}

struct AddressSettingsState: Equatable {
    var businessAddress = false
    var autoAccept = false
    var autoAcceptIncognito = false
    var autoReply = ""

    init() {}

    init(settings: AddressSettings) {
        self.businessAddress = settings.businessAddress
        self.autoAccept = settings.autoAccept != nil
        self.autoAcceptIncognito = settings.autoAccept?.acceptIncognito == true
        self.autoReply = settings.autoReply?.text ?? ""
    }

    var addressSettings: AddressSettings {
        AddressSettings(
            businessAddress: self.businessAddress,
            autoAccept: self.autoAccept ? AutoAccept(acceptIncognito: self.autoAcceptIncognito) : nil,
            autoReply: self.autoReply.isEmpty ? nil : MsgContent.text(self.autoReply)
        )
    }
}

private func setProfileAddress(_ progressIndicator: Binding<Bool>, _ on: Bool) {
    progressIndicator.wrappedValue = true
    Task {
        do {
            if let u = try await apiSetProfileAddress(on: on) {
                DispatchQueue.main.async {
                    ChatModel.shared.updateUser(u)
                }
            }
            await MainActor.run { progressIndicator.wrappedValue = false }
        } catch let error {
            logger.error("apiSetProfileAddress: \(responseError(error))")
            await MainActor.run { progressIndicator.wrappedValue = false }
        }
    }
}

struct UserAddressSettingsView: View {
    @Environment(\.dismiss) var dismiss: DismissAction
    @EnvironmentObject var chatModel: ChatModel
    @EnvironmentObject var theme: AppTheme
    @Binding var shareViaProfile: Bool
    @State private var rotating = false

    var body: some View {
        List {
            Section(header: Text("Current address").foregroundColor(theme.colors.secondary)) {
                Text(chatModel.userAddress?.connLinkContact.zeroChatUri(short: false) ?? "None")
                    .font(.footnote)
                    .textSelection(.enabled)
            }

            Section {
                Button {
                    rotateAddress()
                } label: {
                    settingsRow("arrow.triangle.2.circlepath", color: theme.colors.primary) {
                        Text(rotating ? "Generating..." : "New address")
                            .foregroundColor(theme.colors.primary)
                    }
                }
                .disabled(rotating)
            }
        }
        .navigationBarTitle("", displayMode: .inline)
    }

    private func rotateAddress() {
        guard !rotating else { return }
        rotating = true
        Task {
            _ = try? await apiDeleteUserAddress()
            if let created = try? await apiCreateUserAddress() {
                await MainActor.run {
                    chatModel.userAddress = UserContactLink(created)
                }
            }
            await MainActor.run { rotating = false }
        }
    }
}

private let zeroNameSaleStart = Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"), year: 2026, month: 12, day: 12, hour: 18))!

struct SetZeroDomainView: View {
    let title: LocalizedStringKey
    let footer: LocalizedStringKey
    let prompt: String
    @State var zeroName: String
    let broadcastWarning: String?
    let save: (String?) async -> Bool
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var theme: AppTheme
    @State private var saving = false
    @State private var original = ""
    @State private var didSave = false
    @State private var editing = false
    @State private var timeToSaleStart = zeroNameSaleStart.timeIntervalSinceNow
    @State private var saleTimer: Timer? = nil
    @FocusState private var nameFocused: Bool

    init(title: LocalizedStringKey, footer: LocalizedStringKey, prompt: String, zeroName: String, broadcastWarning: String? = nil, save: @escaping (String?) async -> Bool) {
        self.title = title
        self.footer = footer
        self.prompt = prompt
        self._zeroName = State(initialValue: zeroName)
        self.broadcastWarning = broadcastWarning
        self.save = save
        self._original = State(initialValue: zeroName)
        self._editing = State(initialValue: zeroName.isEmpty)
    }

    private var changed: Bool {
        normalized(zeroName) != normalized(original)
    }

    private var isValid: Bool {
        guard let d = normalized(zeroName) else { return true }
        return isValidZeroDomain(d)
    }

    var body: some View {
        List {
            Section {
                if editing {
                    ZStack(alignment: .trailing) {
                        TextField(prompt, text: $zeroName)
                            .focused($nameFocused)
                            .autocorrectionDisabled(true)
                            .textInputAutocapitalization(.never)
                            .padding(.trailing, isValid ? 0 : 20)
                        if !isValid {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundColor(.red)
                        }
                    }
                } else {
                    Button {
                        UIPasteboard.general.string = zeroName
                    } label: {
                        HStack {
                            Text(zeroName)
                                .foregroundColor(theme.colors.onBackground)
                            Spacer()
                            Image(systemName: "doc.on.doc")
                                .foregroundColor(theme.colors.secondary)
                        }
                    }
                }
            } header: {
                Text(verbatim: "")
            } footer: {
                Text(footer).foregroundColor(theme.colors.secondary)
            }
            Section {
                if editing {
                    Button {
                        openBrowserAlert(uri: "https://simpl.global/zero/domain")
                    } label: {
                        HStack {
                            Text("Zero Domain Registration")
                            Image(systemName: "arrow.up.right.circle")
                        }
                    }
                    Button {
                        if let w = broadcastWarning, changed {
                            showAlert(w, actions: {[
                                UIAlertAction(title: NSLocalizedString("Save", comment: "alert action"), style: .default) { _ in saveAndDismiss() },
                                UIAlertAction(title: NSLocalizedString("Cancel", comment: "alert action"), style: .cancel)
                            ]})
                        } else {
                            saveAndDismiss()
                        }
                    } label: {
                        Text("Save")
                    }
                    .disabled(saving || !isValid || !changed)
                } else {
                    Button("Remove name") {
                        zeroName = ""
                        editing = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { nameFocused = true }
                    }
                }
            }
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Registration in Progress")
                    Text("Decentralized Zero domain verification is currently being deployed. Public registration ETA is to be announced.")
                        .font(.caption)
                        .foregroundColor(theme.colors.secondary)
                }
            } header: {
                Text("Zero Domain Registration")
                    .foregroundColor(theme.colors.secondary)
            } footer: {
                Text("Learn more and track rollout updates at: [simpl.global/zero/domain](https://simpl.global/zero/domain)")
                    .foregroundColor(theme.colors.secondary)
                    .padding(.bottom)
            }
        }
        .modifier(ThemedBackground(grouped: true))
        .navigationBarTitle("", displayMode: .inline)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if editing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { nameFocused = true }
            }
            if timeToSaleStart > 0 {
                saleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { t in
                    timeToSaleStart = zeroNameSaleStart.timeIntervalSinceNow
                    if timeToSaleStart <= 0 { t.invalidate() }
                }
            }
        }
        .onDisappear {
            saleTimer?.invalidate()
            saleTimer = nil
            if !didSave, !saving, changed, isValid {
                let domain = normalized(zeroName)
                let saveName = save
                showAlert(
                    NSLocalizedString("Save Zero name?", comment: "alert title"),
                    message: broadcastWarning,
                    actions: {[
                        UIAlertAction(title: NSLocalizedString("Save", comment: "alert action"), style: .default) { _ in
                            Task { _ = await saveName(domain) }
                        },
                        UIAlertAction(title: NSLocalizedString("Don't save", comment: "alert action"), style: .cancel)
                    ]}
                )
            }
        }
    }

    private func saveAndDismiss() {
        saving = true
        Task {
            let ok = await save(normalized(zeroName))
            await MainActor.run {
                saving = false
                if ok {
                    didSave = true
                    dismiss()
                }
            }
        }
    }

    private func normalized(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty
                ? nil
                : addZeroTLD((t.hasPrefix("@") || t.hasPrefix("#") ? String(t.dropFirst()) : t).lowercased())
    }

    private func saleCountdown(_ remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining))
        let days = total / 86400
        let dayStr = String.localizedStringWithFormat(
            days == 1
                ? NSLocalizedString("%d day", comment: "time interval")
                : NSLocalizedString("%d days", comment: "time interval"),
            days
        )
        return dayStr + " " + String.localizedStringWithFormat(
            NSLocalizedString("%02d hrs %02d min %02d sec", comment: "countdown"),
            total / 3600 % 24, total / 60 % 60, total % 60
        )
    }

    private func addZeroTLD(_ d: String) -> String {
        if d.contains(".") { d } else { "\(d).zero" }
    }

    private func isValidZeroDomain(_ s: String) -> Bool {
        if s.utf8.count > 253 { return false }
        let labels = s.split(separator: ".", omittingEmptySubsequences: false)
        if labels.count < 2 { return false }
        for label in labels {
            if !isValidNameLabel(label) { return false }
        }
        return true
    }

    private func isValidNameLabel(_ label: Substring) -> Bool {
        if label.isEmpty || label.utf8.count > 63 { return false }
        return label.range(of: "^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$", options: .regularExpression) != nil
    }
}

struct UserAddressView_Previews: PreviewProvider {
    static var previews: some View {
        let chatModel = ChatModel()
        chatModel.userAddress = UserContactLink(CreatedConnLink(connFullLink: "https://simpl.global/contact#/?v=1&smp=smp%3A%2F%2FPQUV2eL0t7OStZOoAsPEV2QYWt4-xilbakvGUGOItUo%3D%40zerorelay.simpl.global%2FK1rslx-m5bpXVIdMZg9NLUZ_8JBm8xTt%23MCowBQYDK2VuAyEALDeVe-sG8mRY22LsXlPgiwTNs9dbiLrNuA7f3ZMAJ2w%3D", connShortLink: nil))

        return Group {
            UserAddressView()
                .environmentObject(chatModel)
            UserAddressView()
                .environmentObject(ChatModel())
        }
    }
}
