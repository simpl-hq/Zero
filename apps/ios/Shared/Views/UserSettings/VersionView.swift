import SwiftUI
import Zero

struct VersionView: View {
    @EnvironmentObject var theme: AppTheme
    @State var versionInfo: CoreVersionInfo?

    var body: some View {
        List {
            Section {
                Text("App version: v\(appVersion ?? "?")")
                Text("App build: \(appBuild ?? "?")")
                if let info = versionInfo {
                    Text("Core version: v\(info.version)")
                    let isHexCommit = info.zeroqCommit.range(of: "^[0-9a-fA-F]{7,40}$", options: .regularExpression) != nil
                    if isHexCommit, let v = try? AttributedString(markdown: "zeroq: v\(info.zeroqVersion) ([\(info.zeroqCommit.prefix(7))](https://github.com/simpl-hq/zero/commit/\(info.zeroqCommit)))") {
                        Text(v)
                    } else {
                        Text("zeroq: v\(info.zeroqVersion) (\(info.zeroqCommit))")
                    }
                }
            }

            Section {
                NavigationLink {
                    DeveloperView()
                        .navigationTitle("Developer")
                        .modifier(ThemedBackground(grouped: true))
                } label: {
                    Text("Developer")
                }
            }

            Section {
                HStack {
                    Spacer()
                    Text("Zero · Simpl LLC")
                        .font(.footnote)
                        .foregroundColor(theme.colors.secondary)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            do {
                versionInfo = try apiGetVersion()
            } catch let error {
                logger.error("apiGetVersion error: \(responseError(error))")
            }
        }
    }
}

struct VersionView_Previews: PreviewProvider {
    static var previews: some View {
        VersionView()
    }
}
