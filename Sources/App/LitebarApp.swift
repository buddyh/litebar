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
            .contextMenu {
                Button {
                    appState.requestRefresh()
                } label: {
                    Label("Refresh Now", systemImage: "arrow.clockwise")
                }

                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }

                Button {
                    appState.openLitebarDirectory()
                } label: {
                    Label("Open ~/.litebar", systemImage: "folder")
                }

                Divider()

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label("Quit Litebar", systemImage: "power")
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
