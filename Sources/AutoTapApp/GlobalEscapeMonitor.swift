import AppKit
import Foundation

@MainActor
final class GlobalEscapeMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var handler: (() -> Void)?

    private(set) var isArmed = false

    @discardableResult
    func start(handler: @escaping () -> Void) -> Bool {
        stop()
        self.handler = handler

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            if self.isEscape(event) {
                Task { @MainActor in
                    self.handler?()
                }
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }

            guard self.isEscape(event) else {
                return event
            }

            self.handler?()
            return nil
        }

        isArmed = globalMonitor != nil && localMonitor != nil
        return isArmed
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }

        globalMonitor = nil
        localMonitor = nil
        handler = nil
        isArmed = false
    }

    private func isEscape(_ event: NSEvent) -> Bool {
        event.keyCode == 53
    }
}
