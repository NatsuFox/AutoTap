import AppKit
import AutoTapCore
import SwiftUI

let autoTapSettingsWindowIdentifier = NSUserInterfaceItemIdentifier("AutoTapSettingsWindow")

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private let logger = AutoTapLog.logger(category: "SettingsWindowController")
    private var window: NSWindow?

    func show(viewModel: AppViewModel) {
        logger.notice("Show requested. Existing window visible: \(window?.isVisible == true ? "yes" : "no").")
        let window = ensureWindow(viewModel: viewModel)
        updateWindow(window, with: viewModel)
        if !window.isVisible {
            if let mainWindow = NSApp.windows.first(where: { $0.identifier == autoTapMainWindowIdentifier }) {
                let origin = CGPoint(
                    x: max(80, mainWindow.frame.midX - (window.frame.width / 2)),
                    y: max(80, mainWindow.frame.midY - (window.frame.height / 2))
                )
                window.setFrameOrigin(origin)
            } else {
                window.center()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        logger.notice("Settings window shown. Visible: \(window.isVisible ? "yes" : "no"), frame: \(NSStringFromRect(window.frame)).")
    }

    private func ensureWindow(viewModel: AppViewModel) -> NSWindow {
        if let window {
            return window
        }

        let window = NSWindow(
            contentRect: NSRect(x: 320, y: 260, width: 520, height: 360),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.identifier = autoTapSettingsWindowIdentifier
        window.setFrameAutosaveName("AutoTapSettingsWindow")
        window.isReleasedWhenClosed = false
        window.delegate = self
        updateWindow(window, with: viewModel)
        self.window = window
        return window
    }

    private func updateWindow(_ window: NSWindow, with viewModel: AppViewModel) {
        window.title = viewModel.strings.settingsTitle
        let rootView = SettingsView(viewModel: viewModel)
        if let hostingView = window.contentView as? NSHostingView<SettingsView> {
            hostingView.rootView = rootView
        } else {
            window.contentView = NSHostingView(rootView: rootView)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window, notification.object as AnyObject === window else {
            return
        }

        window.orderOut(nil)
    }
}
