import SwiftUI
import Zero

struct DeveloperView: View {
    @EnvironmentObject var theme: AppTheme
    @AppStorage(DEFAULT_DEVELOPER_TOOLS) private var developerTools = false
    @AppStorage(GROUP_DEFAULT_CONFIRM_DB_UPGRADES, store: groupDefaults) private var confirmDatabaseUpgrades = false
    @State private var hintsUnchanged = hintDefaultsUnchanged()
    @State private var zeroLinkMode = privacyZeroLinkModeDefault.get()

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack {
            List {
                Section {
                    ExternalLink(destination: URL(string: "https://github.com/simpl-hq/zero")!) {
                        ZStack(alignment: .leading) {
                            Image(colorScheme == .dark ? "github_light" : "github")
                                .resizable()
                                .frame(width: 24, height: 24)
                                .opacity(0.5)
                                .colorMultiply(theme.colors.secondary)
                            Text("Install Zero for terminal")
                                .padding(.leading, 36)
                        }
                    }
                    NavigationLink {
                        TerminalView()
                    } label: {
                        settingsRow("terminal", color: theme.colors.secondary) { Text("Chat console") }
                    }
                    settingsRow("lightbulb.max", color: theme.colors.secondary) {
                        Button("Reset all hints", action: resetHintDefaults)
                        .disabled(hintsUnchanged)
                    }
                    settingsRow("chevron.left.forwardslash.chevron.right", color: theme.colors.secondary) {
                        Toggle("Show developer options", isOn: $developerTools)
                    }
                } header: {
                    Text("")
                } footer: {
                    ((developerTools ? Text("Show:") : Text("Hide:")) + textSpace + Text("Database IDs and Transport isolation option."))
                        .foregroundColor(theme.colors.secondary)
                }

                if developerTools {
                    Section {
                        settingsRow("internaldrive", color: theme.colors.secondary) {
                            Toggle("Confirm database upgrades", isOn: $confirmDatabaseUpgrades)
                        }
                        NavigationLink {
                            StorageView()
                                .navigationBarTitle("", displayMode: .inline)
                                .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            settingsRow("internaldrive", color: theme.colors.secondary) { Text("Storage") }
                        }
                    } header: {
                        Text("Developer options")
                    }
                }
                Section("Deprecated options") {
                    settingsRow("link", color: theme.colors.secondary) {
                        Picker("Zero links", selection: $zeroLinkMode) {
                            ForEach(
                                ZeroLinkMode.values + (ZeroLinkMode.values.contains(zeroLinkMode) ? [] : [zeroLinkMode])
                            ) { mode in
                                Text(mode.text)
                            }
                        }
                    }
                    .frame(height: 36)
                    .onChange(of: zeroLinkMode) { mode in
                        privacyZeroLinkModeDefault.set(mode)
                    }
                }
            }
        }
    }

    private func resetHintDefaults() {
        for def in hintDefaults {
            if let val = appDefaults[def] as? Bool {
                UserDefaults.standard.set(val, forKey: def)
            }
        }
        for def in hintGroupDefaults {
            if let val = groupAppDefaults[def] as? Bool {
                groupDefaults.set(val, forKey: def)
            }
        }
        hintsUnchanged = true
    }
}

private func hintDefaultsUnchanged() -> Bool {
    hintDefaults.allSatisfy { def in
        appDefaults[def] as? Bool == UserDefaults.standard.bool(forKey: def)
    } && hintGroupDefaults.allSatisfy { def in
        groupAppDefaults[def] as? Bool == groupDefaults.bool(forKey: def)
    }
}

struct DeveloperView_Previews: PreviewProvider {
    static var previews: some View {
        DeveloperView()
    }
}
