import ApplicationServices
import CoreGraphics
import Foundation

public enum AccessibilityPermissionService {
    public static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    public static func promptIfNeeded() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

public enum QuartzClickPoster {
    public static func postLeftClick(x: Double, y: Double) {
        let point = CGPoint(x: x, y: y)

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return
        }

        postMouseMove(to: point, source: source)
        postMouseEvent(type: .leftMouseDown, at: point, source: source)
        postMouseEvent(type: .leftMouseUp, at: point, source: source)
    }

    private static func postMouseMove(to point: CGPoint, source: CGEventSource) {
        let move = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        move?.post(tap: .cghidEventTap)
    }

    private static func postMouseEvent(type: CGEventType, at point: CGPoint, source: CGEventSource) {
        let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        event?.post(tap: .cghidEventTap)
    }
}

private actor ClickExecutor {
    func perform(clickAction: ClickEngine.ClickAction, x: Double, y: Double) {
        clickAction(x, y)
    }
}

public actor ClickEngine {
    public typealias ClickAction = @Sendable (_ x: Double, _ y: Double) -> Void
    public typealias UnitDidAutoStop = @Sendable (_ unitID: UUID) async -> Void

    enum UnitCompletion {
        case cancelled
        case autoStopped
    }

    private let clickAction: ClickAction
    private let unitDidAutoStop: UnitDidAutoStop?
    private let clickExecutor = ClickExecutor()
    private let logger = AutoTapLog.logger(category: "ClickEngine")
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var activeUnits: [UUID: ClickUnit] = [:]

    public init(
        clickAction: @escaping ClickAction = { x, y in
            QuartzClickPoster.postLeftClick(x: x, y: y)
        },
        unitDidAutoStop: UnitDidAutoStop? = nil
    ) {
        self.clickAction = clickAction
        self.unitDidAutoStop = unitDidAutoStop
    }

    public func synchronize(with units: [ClickUnit]) {
        let runnableUnits = units
            .map { $0.sanitized() }
            .filter { $0.isRunnable && $0.isRunning }

        let desiredByID = Dictionary(uniqueKeysWithValues: runnableUnits.map { ($0.id, $0) })
        let activeIDs = Set(desiredByID.keys)

        for id in Array(tasks.keys) where !activeIDs.contains(id) {
            stopTask(id, reason: "unit deactivated or removed")
        }

        for (id, unit) in desiredByID {
            guard activeUnits[id] != unit else {
                continue
            }

            if tasks[id] != nil {
                stopTask(id, reason: "unit configuration changed")
            }

            activeUnits[id] = unit

            let clickAction = self.clickAction
            let clickExecutor = self.clickExecutor
            let engine = self
            logger.info("Starting runner for \(unit.name) [\(unit.id.uuidString)] kind \(unit.kind.displayName), frequency \(String(format: "%.2f", unit.frequencyHz)) Hz, points \(unit.pointCount), run duration \(String(format: "%.0f", unit.runDurationSeconds))s.")

            tasks[id] = Task.detached(priority: .userInitiated) {
                let completion = await UnitRunner.run(
                    unit: unit,
                    clickAction: clickAction,
                    clickExecutor: clickExecutor
                )
                await engine.handleRunnerCompletion(for: unit.id, completion: completion)
            }
        }
    }

    public func stopAll() {
        logger.notice("Stopping all click runners. Active count: \(tasks.count).")
        for id in Array(tasks.keys) {
            stopTask(id, reason: "stopAll requested")
        }
    }

    private func handleRunnerCompletion(for unitID: UUID, completion: UnitCompletion) async {
        switch completion {
        case .cancelled:
            return
        case .autoStopped:
            let unitName = activeUnits[unitID]?.name ?? "Unknown Unit"
            logger.notice("Runner for \(unitName) [\(unitID.uuidString)] ended because its run duration elapsed.")
            tasks.removeValue(forKey: unitID)
            activeUnits.removeValue(forKey: unitID)
            if let unitDidAutoStop {
                await unitDidAutoStop(unitID)
            }
        }
    }

    private func stopTask(_ id: UUID, reason: String) {
        guard tasks[id] != nil || activeUnits[id] != nil else {
            return
        }

        let unitName = activeUnits[id]?.name ?? "Unknown Unit"
        logger.info("Stopping runner for \(unitName) [\(id.uuidString)] reason: \(reason).")

        tasks[id]?.cancel()
        tasks.removeValue(forKey: id)
        activeUnits.removeValue(forKey: id)
    }
}

private enum UnitRunner {
    static func run(
        unit: ClickUnit,
        clickAction: @escaping ClickEngine.ClickAction,
        clickExecutor: ClickExecutor
    ) async -> ClickEngine.UnitCompletion {
        let logger = AutoTapLog.logger(category: "UnitRunner")
        logger.notice("Runner active for \(unit.name) [\(unit.id.uuidString)] kind \(unit.kind.displayName), frequency \(String(format: "%.2f", unit.frequencyHz)) Hz.")
        defer {
            logger.notice("Runner exited for \(unit.name) [\(unit.id.uuidString)].")
        }

        switch unit.kind {
        case .singlePoint:
            return await runSingle(unit: unit, clickAction: clickAction, clickExecutor: clickExecutor)
        case .pointGroup:
            return await runGroup(unit: unit, clickAction: clickAction, clickExecutor: clickExecutor)
        }
    }

    private static func runSingle(
        unit: ClickUnit,
        clickAction: @escaping ClickEngine.ClickAction,
        clickExecutor: ClickExecutor
    ) async -> ClickEngine.UnitCompletion {
        let interval = nanoseconds(forFrequency: unit.frequencyHz)
        let deadline = deadlineNanoseconds(forDuration: unit.runDurationSeconds)

        while !Task.isCancelled {
            if hasReached(deadline) {
                return .autoStopped
            }

            await clickExecutor.perform(clickAction: clickAction, x: unit.singlePoint.x, y: unit.singlePoint.y)

            if await sleep(interval, until: deadline) {
                return .autoStopped
            }
        }

        return .cancelled
    }

    private static func runGroup(
        unit: ClickUnit,
        clickAction: @escaping ClickEngine.ClickAction,
        clickExecutor: ClickExecutor
    ) async -> ClickEngine.UnitCompletion {
        let points = unit.groupPoints
        guard !points.isEmpty else {
            return .cancelled
        }

        let cycleInterval = nanoseconds(forFrequency: unit.frequencyHz)
        let spacing = points.count > 1
            ? max(UInt64(1_000_000), cycleInterval / UInt64(points.count))
            : 0
        let deadline = deadlineNanoseconds(forDuration: unit.runDurationSeconds)

        while !Task.isCancelled {
            let cycleStart = DispatchTime.now().uptimeNanoseconds

            for (index, point) in points.enumerated() {
                if Task.isCancelled {
                    return .cancelled
                }
                if hasReached(deadline) {
                    return .autoStopped
                }

                await clickExecutor.perform(clickAction: clickAction, x: point.x, y: point.y)

                if index < points.count - 1, spacing > 0 {
                    if await sleep(spacing, until: deadline) {
                        return .autoStopped
                    }
                }
            }

            let elapsed = DispatchTime.now().uptimeNanoseconds - cycleStart
            if elapsed < cycleInterval {
                if await sleep(cycleInterval - elapsed, until: deadline) {
                    return .autoStopped
                }
            }
        }

        return .cancelled
    }

    private static func nanoseconds(forFrequency frequencyHz: Double) -> UInt64 {
        let sanitizedFrequency = min(max(frequencyHz, 0.1), 200)
        let interval = max(1, (1_000_000_000 / sanitizedFrequency).rounded())
        return UInt64(interval)
    }

    private static func deadlineNanoseconds(forDuration durationSeconds: Double) -> UInt64? {
        guard durationSeconds > 0 else {
            return nil
        }

        return DispatchTime.now().uptimeNanoseconds + UInt64(durationSeconds * 1_000_000_000)
    }

    private static func hasReached(_ deadline: UInt64?) -> Bool {
        guard let deadline else {
            return false
        }
        return DispatchTime.now().uptimeNanoseconds >= deadline
    }

    private static func sleep(_ nanoseconds: UInt64, until deadline: UInt64?) async -> Bool {
        guard nanoseconds > 0 else {
            return hasReached(deadline)
        }

        var sleepDuration = nanoseconds
        if let deadline {
            let now = DispatchTime.now().uptimeNanoseconds
            if now >= deadline {
                return true
            }
            sleepDuration = min(sleepDuration, deadline - now)
        }

        do {
            try await Task.sleep(nanoseconds: sleepDuration)
        } catch {
            return false
        }

        return hasReached(deadline)
    }
}
