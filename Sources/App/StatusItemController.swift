import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let appState: AppState
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var monitor: Any?

    init(appState: AppState) {
        self.appState = appState
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
        }
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self

        observeState()
        updateIcon()
    }

    // Recursive withObservationTracking to catch any state change
    private func observeState() {
        withObservationTracking {
            _ = appState.totalWarnings
            _ = appState.isLoading
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeState()
                self.updateIcon()
            }
        }
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "cylinder.split.1x2",
                            accessibilityDescription: "Litebar")
        image?.isTemplate = true
        button.image = image
        let warnings = appState.totalWarnings
        if warnings > 0 {
            button.title = "\(warnings)"
            button.imagePosition = .imageLeft
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // Fresh controller guarantees current state on every open
            let content = NSHostingController(
                rootView: MenuBarPanel().environment(appState))
            popover.contentViewController = content
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
