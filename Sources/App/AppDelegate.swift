import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState?
    private var statusController: StatusItemController?

    func configure(appState: AppState) {
        self.appState = appState
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard let appState else { return }
        statusController = StatusItemController(appState: appState)
        appState.startAutoRefresh()
        appState.startConfigWatch()

        // SwiftUI opens a lifecycle WindowGroup on launch — close it immediately
        DispatchQueue.main.async {
            NSApp.windows
                .filter { $0.title.contains("Lifecycle") }
                .forEach { $0.orderOut(nil) }
        }
    }
}
