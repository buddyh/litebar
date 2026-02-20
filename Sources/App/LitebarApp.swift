import SwiftUI

@main
struct LitebarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State var appState: AppState

    init() {
        let state = AppState(autoStart: false)
        _appState = State(initialValue: state)
        delegate.configure(appState: state)
    }

    var body: some Scene {
        // Hidden lifecycle window keeps SwiftUI runtime alive for Settings scene
        WindowGroup("LitebarLifecycle") {
            Color.clear.frame(width: 1, height: 1)
        }
        .defaultSize(width: 20, height: 20)
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView()
                .environment(appState)
        }
        .windowResizability(.contentSize)
    }
}
