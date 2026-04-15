import AppKit
import Combine
import AutoTapCore

let autoTapMiniBarWindowIdentifier = NSUserInterfaceItemIdentifier("AutoTapMiniBarWindow")

@MainActor
final class MiniBarWindowController: NSObject, NSWindowDelegate {
    static let shared = MiniBarWindowController()

    private let logger = AutoTapLog.logger(category: "MiniBarWindowController")
    private var miniWindow: NSWindow?
    private var hiddenMainWindow: NSWindow?
    private weak var fullWindow: NSWindow?
    private weak var viewModel: AppViewModel?
    private var viewModelObservation: AnyCancellable?
    private var contentController: MiniBarContentController?

    var isVisible: Bool {
        miniWindow?.isVisible == true
    }

    func toggle(viewModel: AppViewModel, sourceWindow: NSWindow? = nil) {
        logger.notice("Toggle requested. Mini window visible: \(isVisible ? "yes" : "no").")
        if isVisible {
            restoreFullWindow()
        } else {
            show(viewModel: viewModel, sourceWindow: sourceWindow)
        }
    }

    func show(viewModel: AppViewModel, sourceWindow: NSWindow? = nil) {
        let preferredWindow = sourceWindow ?? resolvedFullWindow(preferVisible: true)
        fullWindow = preferredWindow
        logger.notice("Show requested. Full window found: \(preferredWindow != nil ? "yes" : "no").")

        let miniWindow = ensureWindow()
        let contentController = ensureContentController(for: miniWindow)
        bind(to: viewModel)
        contentController.update(with: viewModel, strings: viewModel.strings)
        miniWindow.title = viewModel.strings.showMiniBar

        position(window: miniWindow, near: preferredWindow)
        bringMiniWindowForward(forceActivate: true)

        DispatchQueue.main.async { [weak self, weak miniWindow, weak preferredWindow] in
            guard let self, let miniWindow else {
                return
            }
            self.bringMiniWindowForward(forceActivate: false)
            self.hideResolvedFullWindowIfNeeded(excluding: miniWindow, preferredWindow: preferredWindow)
        }
    }

    func bringMiniWindowForward(forceActivate: Bool) {
        guard let miniWindow else {
            logger.error("Bring requested but mini window is missing.")
            return
        }

        if forceActivate {
            NSApp.activate(ignoringOtherApps: true)
        }

        miniWindow.orderFrontRegardless()
        miniWindow.makeKeyAndOrderFront(nil)
        miniWindow.displayIfNeeded()
        logger.notice("Mini window brought forward. Visible: \(miniWindow.isVisible ? "yes" : "no"), frame: \(NSStringFromRect(miniWindow.frame)).")
    }

    func restoreFullWindow() {
        miniWindow?.orderOut(nil)

        let targetWindow = hiddenMainWindow ?? resolvedFullWindow(preferVisible: false)
        guard let targetWindow else {
            logger.error("Restore requested but no target window is available.")
            return
        }

        fullWindow = targetWindow
        hiddenMainWindow = nil
        MainWindowRegistry.shared.window = targetWindow
        NSApp.activate(ignoringOtherApps: true)
        targetWindow.makeKeyAndOrderFront(nil)
        targetWindow.orderFrontRegardless()
        logger.notice("Restored main window at frame \(NSStringFromRect(targetWindow.frame)).")
    }

    func windowWillClose(_ notification: Notification) {
        logger.notice("Mini bar close requested by window system. Keeping app running without restoring the main window.")
        miniWindow?.orderOut(nil)
    }

    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        guard window.identifier == autoTapMiniBarWindowIdentifier else {
            return true
        }

        logger.notice("Mini bar zoom requested. Restoring full window instead.")
        restoreFullWindow()
        return false
    }

    private func ensureWindow() -> NSWindow {
        if let miniWindow {
            return miniWindow
        }

        logger.notice("Creating mini bar window shell.")
        let miniWindow = NSWindow(
            contentRect: NSRect(x: 240, y: 240, width: 352, height: 116),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        logger.notice("Mini bar window allocated.")
        miniWindow.identifier = autoTapMiniBarWindowIdentifier
        miniWindow.setFrameAutosaveName("AutoTapMiniBarWindow")
        miniWindow.delegate = self
        miniWindow.minSize = NSSize(width: 264, height: 116)
        miniWindow.level = .floating
        miniWindow.hidesOnDeactivate = false
        miniWindow.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        miniWindow.isReleasedWhenClosed = false
        miniWindow.isMovableByWindowBackground = true
        miniWindow.hasShadow = true
        self.miniWindow = miniWindow
        logger.notice("Created mini bar window shell successfully.")
        return miniWindow
    }

    private func ensureContentController(for miniWindow: NSWindow) -> MiniBarContentController {
        if let contentController {
            return contentController
        }

        let contentController = MiniBarContentController()
        contentController.onRestore = { [weak self] in
            self?.restoreFullWindow()
        }
        contentController.onPrimaryAction = { [weak self] in
            guard let self, let viewModel = self.viewModel else {
                self?.logger.error("Primary mini bar action requested without a view model.")
                return
            }
            if viewModel.isAnyRunning || viewModel.hasActiveCountdown {
                viewModel.stopAll()
            } else {
                viewModel.startAll()
            }
            self.refreshContent()
        }
        contentController.runMenuProvider = { [weak self] in
            self?.makeRunMenu()
        }
        contentController.onSettings = { [weak self] in
            guard let self, let viewModel = self.viewModel else {
                self?.logger.error("Settings requested from mini bar without a view model.")
                return
            }
            SettingsWindowController.shared.show(viewModel: viewModel)
            self.logger.notice("Settings opened from mini bar.")
        }
        miniWindow.contentViewController = contentController
        self.contentController = contentController
        logger.notice("Attached mini bar content controller.")
        return contentController
    }

    private func bind(to viewModel: AppViewModel) {
        let needsRebind = self.viewModel !== viewModel || viewModelObservation == nil
        self.viewModel = viewModel
        guard needsRebind else {
            return
        }

        viewModelObservation = viewModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshContent()
            }
        logger.notice("Bound mini bar to app view model updates.")
    }

    private func refreshContent() {
        guard let viewModel, let contentController else {
            return
        }
        contentController.update(with: viewModel, strings: viewModel.strings)
    }

    private func position(window miniWindow: NSWindow, near baseWindow: NSWindow?) {
        let screen = baseWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 80, y: 80, width: 1280, height: 720)
        let windowSize = miniWindow.frame.size

        var origin: CGPoint
        if let baseWindow {
            origin = CGPoint(
                x: baseWindow.frame.minX,
                y: baseWindow.frame.maxY - windowSize.height
            )
        } else {
            origin = CGPoint(
                x: visibleFrame.midX - (windowSize.width / 2),
                y: visibleFrame.midY - (windowSize.height / 2)
            )
        }

        origin.x = min(max(visibleFrame.minX + 16, origin.x), visibleFrame.maxX - windowSize.width - 16)
        origin.y = min(max(visibleFrame.minY + 16, origin.y), visibleFrame.maxY - windowSize.height - 16)
        miniWindow.setFrameOrigin(origin)
        logger.notice("Mini window positioned at \(NSStringFromPoint(origin)) within visible frame \(NSStringFromRect(visibleFrame)).")
    }

    private func hideResolvedFullWindowIfNeeded(excluding miniWindow: NSWindow, preferredWindow: NSWindow?) {
        guard miniWindow.isVisible else {
            return
        }

        let targetWindow = preferredWindow ?? resolvedFullWindow(preferVisible: true)
        guard let targetWindow, targetWindow !== miniWindow else {
            logger.error("Mini bar became visible but no main window target was available to hide.")
            return
        }

        fullWindow = targetWindow
        hiddenMainWindow = targetWindow
        MainWindowRegistry.shared.window = targetWindow
        targetWindow.orderOut(nil)
        logger.notice("Main window hidden after mini bar became visible.")
    }

    private func resolvedFullWindow(preferVisible: Bool) -> NSWindow? {
        if let trackedWindow = MainWindowRegistry.shared.window,
           trackedWindow.identifier != autoTapMiniBarWindowIdentifier,
           trackedWindow.identifier != autoTapSettingsWindowIdentifier,
           !trackedWindow.styleMask.contains(.borderless),
           (!preferVisible || (trackedWindow.isVisible && !trackedWindow.isMiniaturized))
        {
            return trackedWindow
        }

        if let activeWindow = (NSApp.keyWindow ?? NSApp.mainWindow),
           activeWindow.identifier != autoTapMiniBarWindowIdentifier,
           activeWindow.identifier != autoTapSettingsWindowIdentifier,
           !activeWindow.styleMask.contains(.borderless),
           (!preferVisible || (activeWindow.isVisible && !activeWindow.isMiniaturized))
        {
            return activeWindow
        }

        let windows = NSApp.windows.filter { window in
            window.identifier == autoTapMainWindowIdentifier
                && window.identifier != autoTapMiniBarWindowIdentifier
                && window.identifier != autoTapSettingsWindowIdentifier
                && !window.styleMask.contains(.borderless)
        }

        if preferVisible,
           let visibleWindow = windows.first(where: { $0.isVisible && !$0.isMiniaturized })
        {
            return visibleWindow
        }

        if let mainWindow = windows.first(where: { $0.isMainWindow || $0.isKeyWindow }) {
            return mainWindow
        }

        if let fullWindow,
           windows.contains(where: { $0 === fullWindow })
        {
            return fullWindow
        }

        return windows.first
            ?? NSApp.windows.first(where: { window in
                window.identifier != autoTapMiniBarWindowIdentifier
                    && window.identifier != autoTapSettingsWindowIdentifier
                    && !window.styleMask.contains(.borderless)
                    && (window.isVisible || !preferVisible)
            })
    }

    private func makeRunMenu() -> NSMenu? {
        guard let viewModel else {
            logger.error("Run menu requested without a view model.")
            return nil
        }

        let strings = viewModel.strings
        let menu = NSMenu()

        if viewModel.isAnyRunning || viewModel.hasActiveCountdown {
            let stopItem = NSMenuItem(title: strings.stopAll, action: #selector(handleStopAllMenuItem(_:)), keyEquivalent: "")
            stopItem.target = self
            menu.addItem(stopItem)
            return menu
        }

        let startAllItem = NSMenuItem(title: strings.startAll, action: #selector(handleStartAllMenuItem(_:)), keyEquivalent: "")
        startAllItem.target = self
        menu.addItem(startAllItem)

        if viewModel.units.isEmpty {
            menu.addItem(.separator())
            let emptyItem = NSMenuItem(title: strings.noUnitSelected, action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return menu
        }

        menu.addItem(.separator())
        for unit in viewModel.units {
            let item = NSMenuItem(title: unit.name, action: #selector(handleStartUnitMenuItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = unit.id
            menu.addItem(item)
        }
        return menu
    }

    @objc private func handleStartAllMenuItem(_ sender: NSMenuItem) {
        viewModel?.startAll()
    }

    @objc private func handleStopAllMenuItem(_ sender: NSMenuItem) {
        viewModel?.stopAll()
    }

    @objc private func handleStartUnitMenuItem(_ sender: NSMenuItem) {
        guard let unitID = sender.representedObject as? UUID else {
            return
        }
        viewModel?.startUnit(unitID)
    }
}

@MainActor
private final class MiniBarContentController: NSViewController {
    var onRestore: (() -> Void)?
    var onPrimaryAction: (() -> Void)?
    var onSettings: (() -> Void)?
    var runMenuProvider: (() -> NSMenu?)?

    private let materialView = NSVisualEffectView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let restoreButton = NSButton(title: "", target: nil, action: nil)
    private let primaryButton = NSButton(title: "", target: nil, action: nil)
    private let primaryMenuButton = NSButton(title: "", target: nil, action: nil)
    private let settingsButton = NSButton(title: "", target: nil, action: nil)

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 116))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.clear.cgColor
        view = root

        materialView.translatesAutoresizingMaskIntoConstraints = false
        materialView.material = .hudWindow
        materialView.blendingMode = .behindWindow
        materialView.state = .active
        materialView.wantsLayer = true
        materialView.layer?.cornerRadius = 18
        materialView.layer?.masksToBounds = true
        view.addSubview(materialView)

        let contentStack = NSStackView()
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .horizontal
        contentStack.alignment = .centerY
        contentStack.spacing = 14
        materialView.addSubview(contentStack)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(systemSymbolName: "cursorarrow.motionlines", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold))
        iconView.contentTintColor = .controlAccentColor

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 6

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        statusLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        detailLabel.font = .systemFont(ofSize: 12, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 2
        detailLabel.lineBreakMode = .byWordWrapping

        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(statusLabel)
        textStack.addArrangedSubview(detailLabel)

        let buttonStack = NSStackView()
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 8

        let runButtonGroup = NSStackView()
        runButtonGroup.orientation = .horizontal
        runButtonGroup.alignment = .centerY
        runButtonGroup.spacing = 0

        configure(button: restoreButton, action: #selector(handleRestore))
        configure(button: primaryButton, action: #selector(handlePrimaryAction))
        configure(button: primaryMenuButton, action: #selector(handlePrimaryMenuAction))
        configureMenuButton(primaryMenuButton)
        configure(button: settingsButton, action: #selector(handleSettings))

        restoreButton.widthAnchor.constraint(equalToConstant: 30).isActive = true
        primaryButton.widthAnchor.constraint(equalToConstant: 30).isActive = true
        settingsButton.widthAnchor.constraint(equalToConstant: 30).isActive = true

        runButtonGroup.addArrangedSubview(primaryButton)
        runButtonGroup.addArrangedSubview(primaryMenuButton)

        buttonStack.addArrangedSubview(restoreButton)
        buttonStack.addArrangedSubview(runButtonGroup)
        buttonStack.addArrangedSubview(settingsButton)

        contentStack.addArrangedSubview(iconView)
        contentStack.addArrangedSubview(textStack)
        contentStack.addArrangedSubview(buttonStack)

        NSLayoutConstraint.activate([
            materialView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            materialView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            materialView.topAnchor.constraint(equalTo: view.topAnchor),
            materialView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.leadingAnchor.constraint(equalTo: materialView.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: materialView.trailingAnchor, constant: -16),
            contentStack.topAnchor.constraint(equalTo: materialView.topAnchor, constant: 14),
            contentStack.bottomAnchor.constraint(equalTo: materialView.bottomAnchor, constant: -14),

            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),
            textStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 128),
        ])
    }

    func update(with viewModel: AppViewModel, strings: AppStrings) {
        titleLabel.stringValue = strings.appTitle

        if viewModel.hasActiveCountdown {
            statusLabel.stringValue = strings.miniBarCountdown
            statusLabel.textColor = .systemOrange
            if let countdownState = viewModel.countdownState {
                detailLabel.stringValue = strings.countdownShort(countdownState.secondsRemaining)
            } else {
                detailLabel.stringValue = strings.activeUnits(viewModel.units.filter(\.isRunning).count)
            }
        } else if viewModel.isAnyRunning {
            statusLabel.stringValue = strings.miniBarRunning
            statusLabel.textColor = .systemGreen
            detailLabel.stringValue = strings.activeUnits(viewModel.units.filter(\.isRunning).count) + " • " + strings.totalUnits(viewModel.units.count)
        } else {
            statusLabel.stringValue = strings.miniBarIdle
            statusLabel.textColor = .secondaryLabelColor
            detailLabel.stringValue = strings.activeUnits(0) + " • " + strings.totalUnits(viewModel.units.count)
        }

        restoreButton.title = ""
        restoreButton.image = symbolImage(named: "rectangle.expand.vertical", description: strings.restoreFullWindow)
        restoreButton.toolTip = strings.restoreFullWindow
        restoreButton.setAccessibilityLabel(strings.restoreFullWindow)

        if viewModel.isAnyRunning || viewModel.hasActiveCountdown {
            primaryButton.title = ""
            primaryButton.image = symbolImage(named: "stop.fill", description: strings.stopAll)
            primaryButton.toolTip = strings.stopAll
            primaryButton.setAccessibilityLabel(strings.stopAll)
        } else {
            primaryButton.title = ""
            primaryButton.image = symbolImage(named: "play.fill", description: strings.startAll)
            primaryButton.toolTip = strings.startAll
            primaryButton.setAccessibilityLabel(strings.startAll)
        }

        primaryMenuButton.title = ""
        primaryMenuButton.image = symbolImage(named: "chevron.down", description: strings.selectUnit)
        primaryMenuButton.toolTip = strings.selectUnit
        primaryMenuButton.setAccessibilityLabel(strings.selectUnit)

        settingsButton.title = ""
        settingsButton.image = symbolImage(named: "gearshape", description: strings.openSettings)
        settingsButton.toolTip = strings.openSettings
        settingsButton.setAccessibilityLabel(strings.openSettings)
    }

    private func configure(button: NSButton, action: Selector) {
        button.target = self
        button.action = action
        button.bezelStyle = .texturedRounded
        button.setButtonType(.momentaryPushIn)
        button.imagePosition = .imageOnly
        button.controlSize = .small
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .labelColor
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
    }

    private func configureMenuButton(_ button: NSButton) {
        button.widthAnchor.constraint(equalToConstant: 22).isActive = true
    }

    private func symbolImage(named systemName: String, description: String) -> NSImage? {
        NSImage(systemSymbolName: systemName, accessibilityDescription: description)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
    }

    @objc private func handleRestore() {
        onRestore?()
    }

    @objc private func handlePrimaryAction() {
        onPrimaryAction?()
    }

    @objc private func handlePrimaryMenuAction(_ sender: NSButton) {
        guard let menu = runMenuProvider?(), !menu.items.isEmpty else {
            return
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    @objc private func handleSettings() {
        onSettings?()
    }
}
