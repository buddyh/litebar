import SwiftUI

@main
struct LitebarApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel()
                .environment(appState)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "cylinder.split.1x2")
                if appState.totalWarnings > 0 {
                    Text("\(appState.totalWarnings)")
                        .font(.system(size: 9, weight: .bold))
                }
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
