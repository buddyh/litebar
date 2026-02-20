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

        WindowGroup("LitebarLifecycleKeepalive") {
            HiddenWindowView()
        }
        .defaultSize(width: 20, height: 20)
        .windowStyle(.hiddenTitleBar)

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
    var body: some View {
        Button {
            NotificationCenter.default.post(name: .litebarOpenSettings, object: nil)
        } label: {
            Label("Settings", systemImage: "gearshape")
        }
    }
}

private struct OpenAboutMenuItem: View {
    var body: some View {
        Button {
            NotificationCenter.default.post(name: .litebarOpenAbout, object: nil)
        } label: {
            Label("About Litebar", systemImage: "info.circle")
        }
    }
}

private struct HiddenWindowView: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 20, height: 20)
            .onReceive(NotificationCenter.default.publisher(for: .litebarOpenSettings)) { _ in
                Task { @MainActor in
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .litebarOpenAbout)) { _ in
                Task { @MainActor in
                    openWindow(id: "about")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            .onAppear {
                guard let window = NSApp.windows.first(where: { $0.title == "LitebarLifecycleKeepalive" }) else { return }
                window.styleMask = [.borderless]
                window.collectionBehavior = [.auxiliary, .ignoresCycle, .transient, .canJoinAllSpaces]
                window.isExcludedFromWindowsMenu = true
                window.level = .floating
                window.isOpaque = false
                window.alphaValue = 0
                window.backgroundColor = .clear
                window.hasShadow = false
                window.ignoresMouseEvents = true
                window.canHide = false
                window.setContentSize(NSSize(width: 1, height: 1))
                window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
            }
    }
}

extension Notification.Name {
    static let litebarOpenSettings = Notification.Name("litebarOpenSettings")
    static let litebarOpenAbout = Notification.Name("litebarOpenAbout")
}
