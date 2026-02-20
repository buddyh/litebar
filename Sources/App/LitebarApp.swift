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

                OpenSettingsMenuItem()
                OpenAboutMenuItem()

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
        .windowResizability(.contentSize)

        Window("About Litebar", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}

private struct OpenSettingsMenuItem: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button {
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            Label("Settings", systemImage: "gearshape")
        }
    }
}

private struct OpenAboutMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            openWindow(id: "about")
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            Label("About Litebar", systemImage: "info.circle")
        }
    }
}
