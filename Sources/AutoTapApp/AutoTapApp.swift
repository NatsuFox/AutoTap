import AppKit
import SwiftUI

let autoTapMainWindowIdentifier = NSUserInterfaceItemIdentifier("AutoTapMainWindow")

final class MainWindowRegistry {
    static let shared = MainWindowRegistry()
    weak var window: NSWindow?
}

@MainActor
func openAutoTapSettings() {
    if NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
        return
    }

    _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
}

@MainActor
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            _ = self.activateMainWindow(forceActivate: true)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        DispatchQueue.main.async {
            _ = self.activateMainWindow(forceActivate: true)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        !activateMainWindow(forceActivate: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @discardableResult
    private func activateMainWindow(forceActivate: Bool) -> Bool {
        if forceActivate {
            NSApp.activate(ignoringOtherApps: true)
        }

        if let activeWindow = (NSApp.keyWindow ?? NSApp.mainWindow), activeWindow.isVisible {
            activeWindow.orderFrontRegardless()
            activeWindow.makeKeyAndOrderFront(nil)
            return true
        }

        if let floatingPanel = NSApp.windows
            .compactMap({ $0 as? NSPanel })
            .first(where: { $0.isVisible && $0.canBecomeKey })
        {
            floatingPanel.orderFrontRegardless()
            floatingPanel.makeKeyAndOrderFront(nil)
            return true
        }

        guard let window = NSApp.windows.first(where: { $0.identifier == autoTapMainWindowIdentifier })
            ?? NSApp.windows.first(where: { !$0.styleMask.contains(.borderless) && $0.isVisible })
        else {
            return false
        }

        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        return true
    }
}

@main
@MainActor
struct AutoTapApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appDelegate
    @StateObject private var viewModel: AppViewModel

    init() {
        let escapeMonitor = GlobalEscapeMonitor()
        let screenPointPicker = ScreenPointPicker()
        _viewModel = StateObject(
            wrappedValue: AppViewModel(
                escapeMonitor: escapeMonitor,
                screenPointPicker: screenPointPicker
            )
        )
    }

    var body: some Scene {
        WindowGroup(viewModel.strings.appTitle) {
            ContentView(viewModel: viewModel)
        }

        Settings {
            SettingsView(viewModel: viewModel)
        }
    }
}
