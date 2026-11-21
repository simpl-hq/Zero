import SwiftUI
import Zero

struct UserPicker: View {
    @EnvironmentObject var m: ChatModel
    @EnvironmentObject var theme: AppTheme
    @Environment(\.dynamicTypeSize) private var userFont: DynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase: ScenePhase
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    @Binding var userPickerShown: Bool
    @Binding var activeSheet: UserPickerSheet?
    @State private var currentUser: Int64?
    @State private var switchingProfile = false
    @State private var frameWidth: CGFloat = 0
    @State private var resetScroll = ResetScrollAction()
    @State private var showNewIdentityDialog = false
    @State private var showBurnDisposableDialog = false
    @State private var identityActionInProgress = false
    @State private var disposableParentUserId: Int64 = Int64(kcDisposableParentUserId.get() ?? "") ?? 0

    private let imageSize: CGFloat = 44
    private let rowPadding: CGFloat = 16
    private let rowVerticalPadding: CGFloat = 11
    private let sectionSpacing: CGFloat = 35
    private var sectionHorizontalPadding: CGFloat { frameWidth > 375 ? 20 : 16 }
    private let sectionShape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    var body: some View {
        let sectionWidth = max(frameWidth - sectionHorizontalPadding * 2, 0)
        let stopped = m.chatRunning != true || identityActionInProgress
        let hasDisposableParent = disposableParentUserId > 0
            && m.currentUser?.userId != Int64(disposableParentUserId)
            && m.users.contains(where: { $0.user.userId == Int64(disposableParentUserId) })
        VStack(spacing: sectionSpacing) {
            if let user = m.currentUser {
                StickyScrollView(resetScroll: $resetScroll) {
                    HStack(spacing: rowPadding) {
                        HStack {
                            ProfileImage(imageStr: user.image, size: imageSize, color: Color(uiColor: .tertiarySystemGroupedBackground))
                                .padding(.trailing, 6)
                            profileName(user).lineLimit(1)
                        }
                        .padding(rowPadding)
                        .frame(width: sectionWidth, alignment: .leading)
                        .modifier(ListRow { activeSheet = .currentProfile })
                        .clipShape(sectionShape)
                        .disabled(stopped)
                        .opacity(stopped ? 0.4 : 1)
                    }
                    .padding(.horizontal, sectionHorizontalPadding)
                }
                .frame(height: 2 * rowPadding + imageSize)
                .padding(.top, sectionSpacing)
                .overlay(DetermineWidth())
                .onPreferenceChange(DetermineWidth.Key.self) { frameWidth = $0 }
            }
            VStack(spacing: 0) {
                openSheetOnTap("qrcode", title: m.userAddress == nil ? "Create my address" : "My address", sheet: .address, disabled: stopped)
                openSheetOnTap("switch.2", title: "Chat preferences", sheet: .chatPreferences, disabled: stopped)
                if hasDisposableParent {
                    actionRow("flame", title: "Burn identity", tint: .red, disabled: stopped) {
                        showBurnDisposableDialog = true
                    }
                }
                actionRow("arrow.triangle.2.circlepath", title: "New identity", disabled: stopped) {
                    showNewIdentityDialog = true
                }
                openSheetOnTap("desktopcomputer", title: "Use from desktop", sheet: .useFromDesktop, disabled: stopped)
                ZStack(alignment: .trailing) {
                    openSheetOnTap("gearshape", title: "Settings", sheet: .settings, showDivider: false)
                    Image(systemName: colorScheme == .light ? "sun.max" : "moon.fill")
                        .resizable()
                        .scaledToFit()
                        .symbolRenderingMode(.monochrome)
                        .foregroundColor(theme.colors.secondary)
                        .frame(maxWidth: 20, maxHeight: .infinity)
                        .padding(.horizontal, rowPadding)
                        .background(Color(.systemBackground).opacity(0.01))
                        .onTapGesture {
                            if (colorScheme == .light) {
                                ThemeManager.applyTheme(systemDarkThemeDefault.get())
                            } else {
                                ThemeManager.applyTheme(DefaultTheme.LIGHT.themeName)
                            }
                        }
                        .onLongPressGesture {
                            ThemeManager.applyTheme(DefaultTheme.SYSTEM_THEME_NAME)
                        }
                }
            }
            .clipShape(sectionShape)
            .padding(.horizontal, sectionHorizontalPadding)
            .padding(.bottom, sectionSpacing)
        }
        .confirmationDialog(
            "New identity",
            isPresented: $showNewIdentityDialog,
            titleVisibility: .visible
        ) {
            Button("Burner identity") {
                rotateIdentity(disposable: true)
            }
            Button("New identity", role: .destructive) {
                rotateIdentity(disposable: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Start a temporary burner session you can destroy anytime, or permanently replace your current identity.")
        }
        .confirmationDialog(
            "Burn identity?",
            isPresented: $showBurnDisposableDialog,
            titleVisibility: .visible
        ) {
            Button("Burn", role: .destructive) {
                burnDisposableIdentity()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This burner identity, its chats, and its address will be permanently deleted, and you will return to your main identity.")
        }
        .onAppear {
            if case .active = scenePhase, hasChatCtrl() {
                currentUser = m.currentUser?.userId
                Task {
                    do {
                        let users = try await listUsersAsync()
                        await MainActor.run {
                            m.users = users
                            currentUser = m.currentUser?.userId
                        }
                    } catch {
                        logger.error("Error loading users \(responseError(error))")
                    }
                }
            }
        }
        .onChange(of: userPickerShown) {
            if !$0 { resetScroll() }
        }
        .modifier(ThemedBackground(grouped: true))
        .disabled(switchingProfile)
    }

    private func userView(_ u: UserInfo, size: CGFloat) -> some View {
        HStack {
            ZStack(alignment: .topTrailing) {
                ProfileImage(imageStr: u.user.image, size: size, color: Color(uiColor: .tertiarySystemGroupedBackground))
                if (u.unreadCount > 0) {
                    userUnreadBadge(u, theme: theme).offset(x: 4, y: -4)
                }
            }
            .padding(.trailing, 6)
            NameWithBadge(Text(u.user.displayName).font(.title2), u.user.profile.localBadge, .title2)
                .lineLimit(1)
        }
        .padding(rowPadding)
        .modifier(ListRow {
            switchingProfile = true
            Task {
                do {
                    try await changeActiveUserAsync_(u.user.userId, viewPwd: nil)
                    await MainActor.run {
                        switchingProfile = false
                        userPickerShown = false
                    }
                } catch {
                    await MainActor.run {
                        switchingProfile = false
                        showAlert(
                            NSLocalizedString("Error switching profile!", comment: "alertTitle"),
                            message: String.localizedStringWithFormat(NSLocalizedString("Error: %@", comment: "alert message"), responseError(error))
                        )
                    }
                }
            }
        })
        .clipShape(sectionShape)
    }

    private func actionRow(_ icon: String, title: LocalizedStringKey, tint: Color? = nil, showDivider: Bool = true, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        ZStack(alignment: .bottom) {
            settingsRow(icon, color: tint ?? theme.colors.secondary) {
                Text(title)
                    .foregroundColor(tint ?? .primary)
                    .opacity(disabled ? 0.4 : 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, rowPadding)
            .padding(.vertical, rowVerticalPadding)
            .modifier(ListRow(action: action))
            .disabled(disabled)
            if showDivider {
                Divider().padding(.leading, 52)
            }
        }
    }

    private func rotateIdentity(disposable: Bool) {
        guard !identityActionInProgress else { return }
        identityActionInProgress = true
        let prevUser = m.currentUser
        let existingParentId = disposableParentUserId > 0 ? Int64(disposableParentUserId) : nil
        Task {
            do {
                let suffix = String(format: "%06x", UInt32.random(in: 0..<0x1000000))
                let prefix = disposable ? "anon" : "zero"
                let newUser = try apiCreateActiveUser(Profile(displayName: "\(prefix)_\(suffix)", fullName: ""))
                _ = try? await apiCreateUserAddress()
                try await changeActiveUserAsync_(newUser.userId, viewPwd: nil)
                if disposable {
                    if existingParentId == nil, let prev = prevUser {
                        await MainActor.run { setDisposableParentUserId(prev.userId) }
                    } else if let parentId = existingParentId, let prev = prevUser, prev.userId != parentId {
                        try? await apiDeleteUser(prev.userId, true, viewPwd: nil)
                    }
                } else {
                    await MainActor.run { setDisposableParentUserId(0) }
                    if let prev = prevUser, prev.userId != newUser.userId {
                        try? await apiDeleteUser(prev.userId, true, viewPwd: nil)
                    }
                    if let parentId = existingParentId, parentId != prevUser?.userId, parentId != newUser.userId {
                        try? await apiDeleteUser(parentId, true, viewPwd: nil)
                    }
                }
                await MainActor.run {
                    identityActionInProgress = false
                    userPickerShown = false
                }
            } catch {
                await MainActor.run {
                    identityActionInProgress = false
                    showAlert(
                        NSLocalizedString("Error creating identity", comment: "alertTitle"),
                        message: responseError(error)
                    )
                }
            }
        }
    }

    private func burnDisposableIdentity() {
        let parentId = Int64(disposableParentUserId)
        guard parentId > 0, !identityActionInProgress else { return }
        identityActionInProgress = true
        let disposableUser = m.currentUser
        Task {
            do {
                try await changeActiveUserAsync_(parentId, viewPwd: nil)
                await MainActor.run { setDisposableParentUserId(0) }
                if let disp = disposableUser, disp.userId != parentId {
                    try? await apiDeleteUser(disp.userId, true, viewPwd: nil)
                }
                await MainActor.run {
                    identityActionInProgress = false
                    userPickerShown = false
                }
            } catch {
                await MainActor.run {
                    identityActionInProgress = false
                    showAlert(
                        NSLocalizedString("Error switching identity", comment: "alertTitle"),
                        message: responseError(error)
                    )
                }
            }
        }
    }

    private func setDisposableParentUserId(_ id: Int64) {
        disposableParentUserId = id
        if id > 0 {
            _ = kcDisposableParentUserId.set(String(id))
        } else {
            _ = kcDisposableParentUserId.remove()
        }
    }

    private func openSheetOnTap(_ icon: String, title: LocalizedStringKey, sheet: UserPickerSheet, showDivider: Bool = true, disabled: Bool = false) -> some View {
        ZStack(alignment: .bottom) {
            settingsRow(icon, color: theme.colors.secondary) {
                Text(title).foregroundColor(.primary).opacity(disabled ? 0.4 : 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, rowPadding)
            .padding(.vertical, rowVerticalPadding)
            .modifier(ListRow { activeSheet = sheet })
            .disabled(disabled)
            if showDivider {
                Divider().padding(.leading, 52)
            }
        }
    }
}

@inline(__always)
func userUnreadBadge(_ userInfo: UserInfo, theme: AppTheme) -> some View {
    UnreadBadge(
        count: userInfo.unreadCount,
        color: userInfo.user.showNtfs ? theme.colors.primary : theme.colors.secondary
    )
}

struct UnreadBadge: View {
    @Environment(\.dynamicTypeSize) private var userFont: DynamicTypeSize
    var count: Int
    var color: Color

    var body: some View {
        let size = dynamicSize(userFont).chatInfoSize
        unreadCountText(count)
            .font(userFont <= .xxxLarge ? .caption : .caption2)
            .fontWeight(.semibold)
            .foregroundColor(color.onSurfaceInk)
            .padding(.horizontal, dynamicSize(userFont).unreadPadding)
            .frame(minWidth: size, minHeight: size)
            .background(color)
            .cornerRadius(dynamicSize(userFont).unreadCorner)
    }
}

struct ListRow: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    @State private var touchDown = false
    let action: () -> Void

    func body(content: Content) -> some View {
        ZStack {
            elevatedSecondarySystemGroupedBackground
            Color(.systemGray4).opacity(touchDown ? 1 : 0)
            content
            TouchOverlay(touchDown: $touchDown, action: action)
        }
    }

    var elevatedSecondarySystemGroupedBackground: Color {
        switch colorScheme {
        case .dark: Color(0xFF2C2C2E)
        default:    Color(0xFFFFFFFF)
        }
    }

    struct TouchOverlay: UIViewRepresentable {
        @Binding var touchDown: Bool
        let action: () -> Void

        func makeUIView(context: Context) -> TouchView {
            let touchView = TouchView()
            let gesture = UILongPressGestureRecognizer(
                target: touchView,
                action: #selector(touchView.longPress(gesture:))
            )
            gesture.delegate = touchView
            gesture.minimumPressDuration = 0
            touchView.addGestureRecognizer(gesture)
            return touchView
        }

        func updateUIView(_ touchView: TouchView, context: Context) {
            touchView.representer = self
        }

        class TouchView: UIView, UIGestureRecognizerDelegate {
            var representer: TouchOverlay?
            private var startLocation: CGPoint?
            private var task: Task<Void, Never>?

            @objc
            func longPress(gesture: UILongPressGestureRecognizer) {
                switch gesture.state {
                case .began:
                    startLocation = gesture.location(in: nil)
                    task = Task {
                        do {
                            try await Task.sleep(nanoseconds: 200_000000)
                            await MainActor.run { representer?.touchDown = true }
                        } catch { }
                    }
                case .ended:
                    if hitTest(gesture.location(in: self), with: nil) == self {
                        representer?.action()
                    }
                    task?.cancel()
                    representer?.touchDown = false
                case .changed:
                    if let startLocation {
                        let location = gesture.location(in: nil)
                        let dx = location.x - startLocation.x
                        let dy = location.y - startLocation.y
                        if sqrt(pow(dx, 2) + pow(dy, 2)) > 10 { gesture.state = .failed }
                    }
                case .cancelled, .failed:
                    task?.cancel()
                    representer?.touchDown = false
                default: break
                }
            }

            func gestureRecognizer(
                _: UIGestureRecognizer,
                shouldRecognizeSimultaneouslyWith: UIGestureRecognizer
            ) -> Bool { true }
        }
    }
}

struct UserPicker_Previews: PreviewProvider {
    static var previews: some View {
        @State var activeSheet: UserPickerSheet?

        let m = ChatModel()
        m.users = [UserInfo.sampleData, UserInfo.sampleData]
        return UserPicker(
            userPickerShown: .constant(true),
            activeSheet: $activeSheet
        )
        .environmentObject(m)
    }
}
