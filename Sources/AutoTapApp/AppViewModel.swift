import Foundation
import AutoTapCore
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    enum RestoreMode {
        case appendNew
        case replaceSelected
    }

    struct CountdownState: Equatable {
        var secondsRemaining: Int
        var label: String
    }

    struct ScreenPickPreview: Equatable {
        var x: Int
        var y: Int

        init(point: CGPoint) {
            x = Int(point.x.rounded())
            y = Int(point.y.rounded())
        }

        var coordinatesSummary: String {
            "X: \(x)  Y: \(y)"
        }
    }

    struct RunProgress: Equatable {
        var remainingSeconds: Int
        var totalSeconds: Int

        var summary: String {
            if remainingSeconds <= 0 {
                return "Stopping…"
            }

            return "\(remainingSeconds)s remaining"
        }
    }

    private enum ScreenPickTarget: Equatable {
        case singlePoint(unitID: UUID)
        case groupPoint(unitID: UUID, pointID: UUID)
    }

    @Published var units: [ClickUnit] {
        didSet {
            handleStateMutation()
        }
    }

    @Published var history: [HistoryRecord] {
        didSet {
            handleStateMutation()
        }
    }

    @Published var selectedUnitID: UUID?
    @Published var isAccessibilityTrusted: Bool
    @Published var isEmergencyStopArmed: Bool
    @Published var startupCountdownSeconds: Int {
        didSet {
            let sanitized = min(max(startupCountdownSeconds, 0), 60)
            if startupCountdownSeconds != sanitized {
                startupCountdownSeconds = sanitized
                return
            }
            handleStateMutation()
        }
    }
    @Published var countdownState: CountdownState?
    @Published var screenPickPrompt: String?
    @Published var screenPickPreview: ScreenPickPreview?
    @Published var autoSaveExecutedUnitsToHistory: Bool {
        didSet {
            handleStateMutation()
        }
    }
    @Published var appLanguage: AppLanguage {
        didSet {
            handleStateMutation()
        }
    }
    @Published var errorMessage: String?
    @Published private(set) var runProgressByUnitID: [UUID: RunProgress] = [:]

    private let store: AppStateStore
    private let escapeMonitor: GlobalEscapeMonitor
    private let screenPointPicker: ScreenPointPicker
    private let historyLimit: Int
    private let logger = AutoTapLog.logger(category: "AppViewModel")

    private lazy var clickEngine: ClickEngine = ClickEngine(unitDidAutoStop: { [weak self] unitID in
        guard let self else {
            return
        }

        await self.handleAutoStop(for: unitID)
    })

    private var countdownTask: Task<Void, Never>?
    private var runProgressTask: Task<Void, Never>?
    private var persistStateTask: Task<Void, Never>?
    private var syncEngineTask: Task<Void, Never>?
    private var pendingStartUnitIDs: Set<UUID> = []
    private var runDeadlinesByUnitID: [UUID: Date] = [:]
    private var activeScreenPickTarget: ScreenPickTarget?
    private var hasFinishedLoading = false

    init(
        store: AppStateStore = AppStateStore(),
        escapeMonitor: GlobalEscapeMonitor,
        screenPointPicker: ScreenPointPicker,
        historyLimit: Int = 100
    ) {
        self.store = store
        self.escapeMonitor = escapeMonitor
        self.screenPointPicker = screenPointPicker
        self.historyLimit = historyLimit
        self.isAccessibilityTrusted = AccessibilityPermissionService.isTrusted()
        self.isEmergencyStopArmed = false
        self.startupCountdownSeconds = 3
        self.countdownState = nil
        self.screenPickPrompt = nil
        self.screenPickPreview = nil
        self.autoSaveExecutedUnitsToHistory = true
        self.appLanguage = .system

        let loadedState = store.load()
        let loadedUnits = loadedState.units.map { $0.stoppedCopy() }
        self.units = loadedUnits.isEmpty ? AppStateStore.defaultState().units : loadedUnits
        self.history = Array(loadedState.history.prefix(historyLimit))
        self.selectedUnitID = self.units.first?.id
        self.startupCountdownSeconds = loadedState.settings.startupCountdownSeconds
        self.autoSaveExecutedUnitsToHistory = loadedState.settings.autoSaveExecutedUnitsToHistory
        self.appLanguage = loadedState.settings.appLanguage
        self.hasFinishedLoading = true

        self.isEmergencyStopArmed = escapeMonitor.start { [weak self] in
            self?.handleEscapePressed()
        }

        logger.notice(
            "App state loaded from \(store.stateURL.path). Units: \(self.units.count), history records: \(self.history.count), accessibility trusted: \(self.isAccessibilityTrusted ? "yes" : "no"), emergency stop armed: \(self.isEmergencyStopArmed ? "yes" : "no"), startup countdown: \(self.startupCountdownSeconds)s, auto-save history: \(self.autoSaveExecutedUnitsToHistory ? "on" : "off"), app language: \(self.appLanguage.rawValue)."
        )

        syncEngine()
    }

    var selectedUnit: ClickUnit? {
        guard let selectedUnitID else {
            return nil
        }

        return units.first(where: { $0.id == selectedUnitID })
    }

    var selectedUnitIndex: Int? {
        guard let selectedUnitID else {
            return nil
        }

        return units.firstIndex(where: { $0.id == selectedUnitID })
    }

    var filteredHistory: [HistoryRecord] {
        guard let selectedKind = selectedUnit?.kind else {
            return history
        }

        let matching = history.filter { $0.kind == selectedKind }
        let other = history.filter { $0.kind != selectedKind }
        return matching + other
    }

    var hasActiveCountdown: Bool {
        countdownState != nil
    }

    var isPickingFromScreen: Bool {
        activeScreenPickTarget != nil
    }

    var isAnyRunning: Bool {
        units.contains(where: { $0.isRunning })
    }

    var canStartClicks: Bool {
        isAccessibilityTrusted && isEmergencyStopArmed && !hasActiveCountdown && !isPickingFromScreen
    }

    var strings: AppStrings {
        AppStrings(preferredLanguage: appLanguage)
    }

    var emergencyStopSummary: String {
        if isEmergencyStopArmed {
            return strings.emergencyStopArmedSummary
        }

        return strings.emergencyStopDisarmedSummary
    }

    func binding(for unitID: UUID) -> Binding<ClickUnit>? {
        guard units.contains(where: { $0.id == unitID }) else {
            return nil
        }

        return Binding(
            get: {
                self.units.first(where: { $0.id == unitID }) ?? ClickUnit.defaultSinglePoint()
            },
            set: { newValue in
                guard let index = self.units.firstIndex(where: { $0.id == unitID }) else {
                    return
                }

                self.units[index] = newValue
            }
        )
    }

    func runProgress(for unitID: UUID) -> RunProgress? {
        runProgressByUnitID[unitID]
    }

    func addSinglePointUnit() {
        let index = units.filter { $0.kind == .singlePoint }.count + 1
        var unit = ClickUnit.defaultSinglePoint(index: index)
        unit.name = strings.defaultSinglePointUnitName(index)
        unit.singlePoint.name = strings.defaultPointName()
        units.append(unit)
        selectedUnitID = unit.id
        logger.info("Added single-point unit \(unit.name) [\(unit.id.uuidString)].")
    }

    func addPointGroupUnit() {
        let index = units.filter { $0.kind == .pointGroup }.count + 1
        var unit = ClickUnit.defaultPointGroup(index: index)
        unit.name = strings.defaultPointGroupUnitName(index)
        unit.groupPoints = unit.groupPoints.enumerated().map { offset, point in
            var adjusted = point
            adjusted.name = strings.defaultPointName(offset + 1)
            return adjusted
        }
        units.append(unit)
        selectedUnitID = unit.id
        logger.info("Added point-group unit \(unit.name) [\(unit.id.uuidString)].")
    }

    func removeUnit(id: UUID) {
        guard let index = units.firstIndex(where: { $0.id == id }) else {
            return
        }

        let removedUnit = units[index]
        units.remove(at: index)
        clearRunTracking(for: id)

        if selectedUnitID == id {
            selectedUnitID = units.first?.id
        }

        logger.info("Removed unit \(removedUnit.name) [\(removedUnit.id.uuidString)].")
    }

    func toggleRunning(_ unitID: UUID) {
        guard let index = units.firstIndex(where: { $0.id == unitID }) else {
            return
        }

        if units[index].isRunning {
            setRunning(false, for: unitID)
            return
        }

        beginStart(for: [unitID], label: strings.startingUnit(units[index].name))
    }

    func setRunning(_ shouldRun: Bool, for unitID: UUID) {
        guard let index = units.firstIndex(where: { $0.id == unitID }) else {
            return
        }

        if shouldRun {
            beginStart(for: [unitID], label: strings.startingUnit(units[index].name))
            return
        }

        units[index].isRunning = false
        clearRunTracking(for: unitID)
        logger.info("Unit \(units[index].name) [\(units[index].id.uuidString)] running state changed to off.")
    }

    func startAll() {
        let stoppedUnits = units.filter { !$0.isRunning }
        let label = stoppedUnits.count == 1
            ? strings.startingUnit(stoppedUnits[0].name)
            : strings.startingUnits(stoppedUnits.count)
        beginStart(
            for: stoppedUnits.map { $0.id },
            label: label
        )
    }

    func startUnit(_ unitID: UUID) {
        guard let index = units.firstIndex(where: { $0.id == unitID }), !units[index].isRunning else {
            return
        }

        beginStart(for: [unitID], label: strings.startingUnit(units[index].name))
    }

    func stopAll() {
        stopAllNow(reason: "stop button pressed")
    }

    func emergencyStop() {
        stopAllNow(reason: "Esc emergency stop")
    }

    func saveHistory(for unitID: UUID, label: String? = nil) {
        guard let unit = units.first(where: { $0.id == unitID }) else {
            return
        }

        let record = HistoryRecord(label: label ?? unit.name, unit: unit)
        history.insert(record, at: 0)

        if history.count > historyLimit {
            history = Array(history.prefix(historyLimit))
        }

        logger.debug("Saved history record \(record.label) for unit \(unit.name). Total records: \(history.count).")
    }

    func removeHistoryRecord(id: UUID) {
        guard let record = history.first(where: { $0.id == id }) else {
            return
        }

        history.removeAll(where: { $0.id == id })
        logger.info("Deleted history record \(record.label) [\(record.id.uuidString)].")
    }

    func restoreHistory(_ recordID: UUID, mode: RestoreMode) {
        guard let record = history.first(where: { $0.id == recordID }) else {
            return
        }

        switch mode {
        case .appendNew:
            let restored = record.snapshot.restoredCopy()
            units.append(restored)
            selectedUnitID = restored.id
            logger.info("Restored history record \(record.label) as a new unit [\(restored.id.uuidString)].")

        case .replaceSelected:
            guard let selectedUnitID,
                  let index = units.firstIndex(where: { $0.id == selectedUnitID })
            else {
                let restored = record.snapshot.restoredCopy()
                units.append(restored)
                self.selectedUnitID = restored.id
                logger.info("No selected unit was available, so history record \(record.label) was restored as a new unit [\(restored.id.uuidString)].")
                return
            }

            var replacement = record.snapshot.restoredCopy()
            replacement.id = selectedUnitID
            units[index] = replacement
            logger.info("Replaced selected unit with history record \(record.label) using unit id \(selectedUnitID.uuidString).")
        }
    }

    func duplicateSelectedUnit() {
        guard let selectedUnit else {
            return
        }

        let duplicate = selectedUnit.restoredCopy()
        units.append(duplicate)
        selectedUnitID = duplicate.id
        logger.info("Duplicated unit \(selectedUnit.name) to new unit id \(duplicate.id.uuidString).")
    }

    func beginSinglePointPick(unitID: UUID) {
        beginScreenPick(
            target: .singlePoint(unitID: unitID),
            prompt: strings.pickSinglePointPrompt
        )
    }

    func beginGroupPointPick(unitID: UUID, pointID: UUID) {
        beginScreenPick(
            target: .groupPoint(unitID: unitID, pointID: pointID),
            prompt: strings.pickGroupPointPrompt
        )
    }

    func isPickingSinglePoint(unitID: UUID) -> Bool {
        activeScreenPickTarget == .singlePoint(unitID: unitID)
    }

    func isPickingGroupPoint(unitID: UUID, pointID: UUID) -> Bool {
        activeScreenPickTarget == .groupPoint(unitID: unitID, pointID: pointID)
    }

    func cancelCurrentScreenPick() {
        guard isPickingFromScreen else {
            return
        }

        screenPointPicker.cancel()
    }

    func addGroupPoint(to unitID: UUID) {
        guard let index = units.firstIndex(where: { $0.id == unitID }) else {
            return
        }

        let nextIndex = units[index].groupPoints.count + 1
        let point = ScreenPoint(name: strings.defaultPointName(nextIndex))
        units[index].groupPoints.append(point)
        logger.info("Added point \(point.name) to group unit \(units[index].name).")
    }

    func removeGroupPoint(unitID: UUID, pointID: UUID) {
        guard let unitIndex = units.firstIndex(where: { $0.id == unitID }) else {
            return
        }

        guard units[unitIndex].groupPoints.count > 1,
              let point = units[unitIndex].groupPoints.first(where: { $0.id == pointID })
        else {
            return
        }

        units[unitIndex].groupPoints.removeAll(where: { $0.id == pointID })
        logger.info("Removed point \(point.name) from group unit \(units[unitIndex].name).")
    }

    func moveGroupPoint(unitID: UUID, pointID: UUID, direction: Int) {
        guard let unitIndex = units.firstIndex(where: { $0.id == unitID }),
              let pointIndex = units[unitIndex].groupPoints.firstIndex(where: { $0.id == pointID })
        else {
            return
        }

        let targetIndex = pointIndex + direction
        guard units[unitIndex].groupPoints.indices.contains(targetIndex) else {
            return
        }

        let movingPointName = units[unitIndex].groupPoints[pointIndex].name
        units[unitIndex].groupPoints.swapAt(pointIndex, targetIndex)
        logger.debug("Moved point \(movingPointName) in unit \(units[unitIndex].name) from index \(pointIndex) to \(targetIndex).")
    }

    func refreshAccessibilityStatus() {
        isAccessibilityTrusted = AccessibilityPermissionService.isTrusted()
        logger.debug("Accessibility status refreshed. Trusted: \(isAccessibilityTrusted ? "yes" : "no").")
    }

    func requestAccessibilityPermission() {
        isAccessibilityTrusted = AccessibilityPermissionService.promptIfNeeded()
        logger.notice("Accessibility permission prompt requested. Trusted now: \(isAccessibilityTrusted ? "yes" : "no").")
    }

    private func beginStart(for unitIDs: [UUID], label: String) {
        let uniqueIDs = Array(Set(unitIDs))
        guard !uniqueIDs.isEmpty else {
            return
        }

        refreshAccessibilityStatus()

        guard isAccessibilityTrusted else {
            errorMessage = strings.accessibilityRequiredError
            requestAccessibilityPermission()
            return
        }

        guard isEmergencyStopArmed else {
            errorMessage = strings.emergencyStopRequiredError
            return
        }

        guard !isPickingFromScreen else {
            errorMessage = strings.finishScreenPickBeforeStartError
            return
        }

        cancelCountdown(reason: nil)

        if autoSaveExecutedUnitsToHistory {
            for unitID in uniqueIDs {
                if let unit = units.first(where: { $0.id == unitID }), !unit.isRunning {
                    saveHistory(for: unitID, label: strings.historySnapshotLabel(unit.name))
                }
            }
        }

        pendingStartUnitIDs = Set(uniqueIDs)
        let countdownSeconds = startupCountdownSeconds

        guard countdownSeconds > 0 else {
            logger.notice("Immediate start requested for \(uniqueIDs.count) unit(s). Emergency stop: Esc.")
            startUnits(with: pendingStartUnitIDs)
            return
        }

        countdownState = CountdownState(secondsRemaining: countdownSeconds, label: label)
        logger.notice("Countdown armed for \(uniqueIDs.count) unit(s). Emergency stop: Esc.")

        countdownTask = Task { [weak self] in
            guard let self else {
                return
            }

            for remaining in stride(from: countdownSeconds, through: 1, by: -1) {
                await MainActor.run {
                    self.countdownState = CountdownState(secondsRemaining: remaining, label: label)
                }

                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
            }

            await MainActor.run {
                self.startUnits(with: self.pendingStartUnitIDs)
            }
        }
    }

    private func startUnits(with unitIDs: Set<UUID>) {
        guard !unitIDs.isEmpty else {
            countdownTask = nil
            countdownState = nil
            return
        }

        var updatedUnits = units
        let startDate = Date()
        for index in updatedUnits.indices {
            if unitIDs.contains(updatedUnits[index].id) {
                updatedUnits[index].isRunning = true

                if updatedUnits[index].runDurationSeconds > 0 {
                    runDeadlinesByUnitID[updatedUnits[index].id] = startDate.addingTimeInterval(updatedUnits[index].runDurationSeconds)
                } else {
                    runDeadlinesByUnitID.removeValue(forKey: updatedUnits[index].id)
                }
            }
        }

        units = updatedUnits
        pendingStartUnitIDs.removeAll()
        countdownTask = nil
        countdownState = nil
        syncRunProgressLoop()

        logger.notice("Started \(unitIDs.count) unit(s). Emergency stop remains Esc.")
    }

    private func cancelCountdown(reason: String?) {
        countdownTask?.cancel()
        countdownTask = nil
        pendingStartUnitIDs.removeAll()

        if countdownState != nil, let reason {
            logger.notice("Countdown cancelled: \(reason).")
        }

        countdownState = nil
    }

    private func beginScreenPick(target: ScreenPickTarget, prompt: String) {
        guard !isAnyRunning else {
            errorMessage = strings.stopClickingBeforePickError
            return
        }

        guard !hasActiveCountdown else {
            errorMessage = strings.cancelCountdownBeforePickError
            return
        }

        activeScreenPickTarget = target
        screenPickPrompt = prompt
        logger.notice("Entered screen-pick mode: \(prompt)")

        screenPointPicker.beginSelection(
            prompt: prompt,
            strings: strings,
            onHover: { [weak self] point in
                Task { @MainActor in
                    self?.screenPickPreview = ScreenPickPreview(point: point)
                }
            },
            onPick: { [weak self] point in
                Task { @MainActor in
                    self?.applyPickedPoint(point)
                }
            },
            onCancel: { [weak self] in
                Task { @MainActor in
                    self?.handleScreenPickCancelled()
                }
            }
        )
    }

    private func applyPickedPoint(_ point: CGPoint) {
        guard let target = activeScreenPickTarget else {
            return
        }

        switch target {
        case let .singlePoint(unitID):
            guard let index = units.firstIndex(where: { $0.id == unitID }) else {
                break
            }

            units[index].singlePoint.x = point.x
            units[index].singlePoint.y = point.y
            logger.info("Picked screen point for unit \(units[index].name) at x \(Int(point.x.rounded())), y \(Int(point.y.rounded())).")

        case let .groupPoint(unitID, pointID):
            guard let unitIndex = units.firstIndex(where: { $0.id == unitID }),
                  let pointIndex = units[unitIndex].groupPoints.firstIndex(where: { $0.id == pointID })
            else {
                break
            }

            units[unitIndex].groupPoints[pointIndex].x = point.x
            units[unitIndex].groupPoints[pointIndex].y = point.y
            logger.info("Picked screen point for \(units[unitIndex].groupPoints[pointIndex].name) in unit \(units[unitIndex].name) at x \(Int(point.x.rounded())), y \(Int(point.y.rounded())).")
        }

        clearScreenPickState()
    }

    private func handleScreenPickCancelled() {
        if activeScreenPickTarget != nil {
            logger.notice("Screen-pick mode cancelled.")
        }
        clearScreenPickState()
    }

    private func clearScreenPickState() {
        activeScreenPickTarget = nil
        screenPickPrompt = nil
        screenPickPreview = nil
    }

    private func handleEscapePressed() {
        if isPickingFromScreen {
            logger.notice("Esc pressed while screen pick was active.")
            screenPointPicker.cancel()
            return
        }

        if hasActiveCountdown || isAnyRunning {
            logger.notice("Esc pressed during countdown or active clicking. Triggering emergency stop.")
            emergencyStop()
        }
    }

    private func stopAllNow(reason: String) {
        cancelCountdown(reason: reason)

        if isPickingFromScreen {
            screenPointPicker.cancel()
        }

        clearAllRunTracking()

        let engine = clickEngine
        Task {
            await engine.stopAll()
        }

        var updatedUnits = units
        for index in updatedUnits.indices {
            updatedUnits[index].isRunning = false
        }
        units = updatedUnits

        logger.notice("All clicking stopped. Reason: \(reason).")
    }

    private func handleAutoStop(for unitID: UUID) {
        guard let index = units.firstIndex(where: { $0.id == unitID }) else {
            return
        }

        units[index].isRunning = false
        clearRunTracking(for: unitID)
        logger.notice("Unit \(units[index].name) auto-stopped after its configured run duration.")
    }

    private func handleStateMutation() {
        guard hasFinishedLoading else {
            return
        }

        if let selectedUnitID, !units.contains(where: { $0.id == selectedUnitID }) {
            self.selectedUnitID = units.first?.id
        }

        schedulePersistState()
        scheduleEngineSync()
    }

    private func schedulePersistState() {
        persistStateTask?.cancel()
        persistStateTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 180_000_000)
            } catch {
                return
            }

            guard let self else {
                return
            }

            self.persistState()
        }
    }

    private func persistState() {
        let persistedUnits = units.map { $0.stoppedCopy() }
        let state = PersistedState(
            units: persistedUnits,
            history: history,
            settings: AppSettings(
                startupCountdownSeconds: startupCountdownSeconds,
                autoSaveExecutedUnitsToHistory: autoSaveExecutedUnitsToHistory,
                appLanguage: appLanguage
            )
        )

        do {
            try store.save(state)
            errorMessage = nil
        } catch {
            errorMessage = strings.persistenceSaveFailed(store.stateURL.path)
            logger.error("Persist failed for \(store.stateURL.path): \(error.localizedDescription).")
        }
    }

    private func scheduleEngineSync() {
        syncEngineTask?.cancel()
        syncEngineTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 80_000_000)
            } catch {
                return
            }

            guard let self else {
                return
            }

            self.syncEngine()
        }
    }

    private func syncEngine() {
        let unitsSnapshot = units
        let engine = clickEngine
        Task {
            await engine.synchronize(with: unitsSnapshot)
        }
    }

    private func refreshRunProgress() {
        let now = Date()
        let activeUnitIDs = Set(units.filter(\.isRunning).map(\.id))

        runDeadlinesByUnitID = runDeadlinesByUnitID.reduce(into: [:]) { partialResult, entry in
            guard activeUnitIDs.contains(entry.key) else {
                return
            }

            partialResult[entry.key] = entry.value
        }

        runProgressByUnitID = runDeadlinesByUnitID.reduce(into: [:]) { partialResult, entry in
            let totalDuration = units.first(where: { $0.id == entry.key })?.runDurationSeconds ?? 0
            let totalSeconds = max(1, Int(totalDuration.rounded()))
            let remainingSeconds = max(0, Int(ceil(entry.value.timeIntervalSince(now))))
            partialResult[entry.key] = RunProgress(
                remainingSeconds: remainingSeconds,
                totalSeconds: totalSeconds
            )
        }
    }

    private func syncRunProgressLoop() {
        refreshRunProgress()

        guard !runDeadlinesByUnitID.isEmpty else {
            runProgressTask?.cancel()
            runProgressTask = nil
            return
        }

        guard runProgressTask == nil else {
            return
        }

        runProgressTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 250_000_000)
                } catch {
                    return
                }

                await MainActor.run {
                    self?.refreshRunProgress()
                }
            }
        }
    }

    private func clearRunTracking(for unitID: UUID) {
        runDeadlinesByUnitID.removeValue(forKey: unitID)
        runProgressByUnitID.removeValue(forKey: unitID)
        syncRunProgressLoop()
    }

    private func clearAllRunTracking() {
        runDeadlinesByUnitID.removeAll()
        runProgressByUnitID = [:]
        syncRunProgressLoop()
    }
}
