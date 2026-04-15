import AppKit
import CoreGraphics
import Foundation

@MainActor
final class ScreenPointPicker {
    private var windows: [ScreenPickOverlayWindow] = []
    private var onHover: ((CGPoint) -> Void)?
    private var onPick: ((CGPoint) -> Void)?
    private var onCancel: (() -> Void)?
    private var isCursorPushed = false
    private var strings = AppStrings(preferredLanguage: .system)

    private(set) var isPicking = false
    private(set) var prompt = ""

    func beginSelection(
        prompt: String,
        strings: AppStrings,
        onHover: @escaping (CGPoint) -> Void,
        onPick: @escaping (CGPoint) -> Void,
        onCancel: @escaping () -> Void
    ) {
        cancel(notify: false)

        self.prompt = prompt
        self.strings = strings
        self.onHover = onHover
        self.onPick = onPick
        self.onCancel = onCancel
        self.isPicking = true

        DispatchQueue.main.async {
            self.presentOverlays()
        }
    }

    func cancel() {
        cancel(notify: true)
    }

    private func cancel(notify: Bool) {
        guard isPicking || !windows.isEmpty else {
            return
        }

        teardownWindows()
        let callback = onCancel
        onHover = nil
        onPick = nil
        onCancel = nil
        prompt = ""
        isPicking = false

        if notify {
            callback?()
        }
    }

    private func finish(with point: CGPoint) {
        guard isPicking else {
            return
        }

        let callback = onPick
        teardownWindows()
        onHover = nil
        onPick = nil
        onCancel = nil
        prompt = ""
        isPicking = false
        callback?(point)
    }

    private func presentOverlays() {
        guard isPicking else {
            return
        }

        let screens = NSScreen.screens
        if windows.count != screens.count {
            windows = screens.map { ScreenPickOverlayWindow(screen: $0) }
        }

        NSApp.activate(ignoringOtherApps: true)

        for (window, screen) in zip(windows, screens) {
            window.setFrame(screen.frame, display: false)
            let overlayView = ScreenPickOverlayView(
                prompt: prompt,
                strings: strings,
                onHover: { [weak self] point in
                    self?.onHover?(point)
                },
                onPick: { [weak self] point in
                    self?.finish(with: point)
                },
                onCancel: { [weak self] in
                    self?.cancel()
                }
            )

            window.contentView = overlayView
            window.makeKeyAndOrderFront(nil)
        }

        if !isCursorPushed {
            NSCursor.crosshair.push()
            isCursorPushed = true
        }
    }

    private func teardownWindows() {
        for window in windows {
            window.orderOut(nil)
        }

        if isCursorPushed {
            NSCursor.pop()
            isCursorPushed = false
        }

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if let mainWindow = NSApp.windows.first(where: { !($0 is ScreenPickOverlayWindow) && $0.isVisible }) {
                mainWindow.makeKeyAndOrderFront(nil)
            }
        }
    }
}

private final class ScreenPickOverlayWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.setFrame(screen.frame, display: false)
        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class ScreenPickOverlayView: NSView {
    private let prompt: String
    private let strings: AppStrings
    private let onHover: (CGPoint) -> Void
    private let onPick: (CGPoint) -> Void
    private let onCancel: () -> Void
    private var trackingAreaRef: NSTrackingArea?
    private var cursorLocation: CGPoint?
    private var cursorQuartzLocation: CGPoint?

    init(
        prompt: String,
        strings: AppStrings,
        onHover: @escaping (CGPoint) -> Void,
        onPick: @escaping (CGPoint) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.prompt = prompt
        self.strings = strings
        self.onHover = onHover
        self.onPick = onPick
        self.onCancel = onCancel
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)

        if let window {
            let screenPoint = NSEvent.mouseLocation
            let windowPoint = window.convertPoint(fromScreen: screenPoint)
            updateCursor(windowPoint: windowPoint, screenPoint: screenPoint)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }

        let trackingAreaRef = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingAreaRef)
        self.trackingAreaRef = trackingAreaRef
    }

    override func mouseMoved(with event: NSEvent) {
        guard let window else {
            return
        }

        let screenPoint = window.convertPoint(toScreen: event.locationInWindow)
        updateCursor(windowPoint: event.locationInWindow, screenPoint: screenPoint)
    }

    private func updateCursor(windowPoint: CGPoint, screenPoint: CGPoint) {
        cursorLocation = convert(windowPoint, from: nil)
        let quartzPoint = CursorCapture.quartzLocation(fromAppKitPoint: screenPoint)
        cursorQuartzLocation = quartzPoint
        onHover(quartzPoint)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else {
            return
        }

        let appKitPoint = window.convertPoint(toScreen: event.locationInWindow)
        let quartzPoint = CursorCapture.quartzLocation(fromAppKitPoint: appKitPoint)
        DispatchQueue.main.async { [onPick] in
            onPick(quartzPoint)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            DispatchQueue.main.async { [onCancel] in
                onCancel()
            }
            return
        }

        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.18).setFill()
        dirtyRect.fill()

        if let cursorLocation {
            let crosshairPath = NSBezierPath()
            crosshairPath.move(to: CGPoint(x: cursorLocation.x, y: bounds.minY))
            crosshairPath.line(to: CGPoint(x: cursorLocation.x, y: bounds.maxY))
            crosshairPath.move(to: CGPoint(x: bounds.minX, y: cursorLocation.y))
            crosshairPath.line(to: CGPoint(x: bounds.maxX, y: cursorLocation.y))
            NSColor.systemYellow.withAlphaComponent(0.9).setStroke()
            crosshairPath.lineWidth = 1
            crosshairPath.stroke()
        }

        drawPromptPanel(in: dirtyRect)
        drawCoordinateBadge()
    }

    private func drawPromptPanel(in dirtyRect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let promptAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ]
        let coordinateAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: NSColor.systemYellow,
            .paragraphStyle: paragraph,
        ]
        let helperAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.86),
            .paragraphStyle: paragraph,
        ]

        let coordinateLine: NSAttributedString
        if let cursorQuartzLocation {
            coordinateLine = NSAttributedString(
                string: strings.coordinatesSummary(x: cursorQuartzLocation.x, y: cursorQuartzLocation.y) + "\n",
                attributes: coordinateAttributes
            )
        } else {
            coordinateLine = NSAttributedString(
                string: strings.moveCursorToInspectCoordinates + "\n",
                attributes: coordinateAttributes
            )
        }

        let attributed = NSMutableAttributedString()
        attributed.append(NSAttributedString(string: prompt + "\n", attributes: promptAttributes))
        attributed.append(coordinateLine)
        attributed.append(NSAttributedString(string: strings.pressEscToCancel, attributes: helperAttributes))

        let textBounds = CGRect(x: bounds.midX - 320, y: bounds.midY - 70, width: 640, height: 180)
        attributed.draw(with: textBounds, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    private func drawCoordinateBadge() {
        guard let cursorLocation, let cursorQuartzLocation else {
            return
        }

        let label = strings.coordinatesSummary(x: cursorQuartzLocation.x, y: cursorQuartzLocation.y)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.white,
        ]

        let text = NSAttributedString(string: label, attributes: attributes)
        let textSize = text.size()
        let padding: CGFloat = 10
        var badgeOrigin = CGPoint(x: cursorLocation.x + 14, y: cursorLocation.y + 14)
        let badgeSize = CGSize(width: textSize.width + padding * 2, height: textSize.height + padding * 2)

        if badgeOrigin.x + badgeSize.width > bounds.maxX - 12 {
            badgeOrigin.x = max(bounds.minX + 12, cursorLocation.x - badgeSize.width - 14)
        }
        if badgeOrigin.y + badgeSize.height > bounds.maxY - 12 {
            badgeOrigin.y = max(bounds.minY + 12, cursorLocation.y - badgeSize.height - 14)
        }

        let badgeRect = CGRect(origin: badgeOrigin, size: badgeSize)
        let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 10, yRadius: 10)
        NSColor.black.withAlphaComponent(0.72).setFill()
        badgePath.fill()

        let textRect = badgeRect.insetBy(dx: padding, dy: padding)
        text.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
}
