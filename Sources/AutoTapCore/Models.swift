import CoreGraphics
import Foundation

public enum ClickUnitKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case singlePoint
    case pointGroup

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .singlePoint:
            return "Single Point"
        case .pointGroup:
            return "Point Group"
        }
    }

    public var defaultName: String {
        switch self {
        case .singlePoint:
            return "Single Point Unit"
        case .pointGroup:
            return "Point Group Unit"
        }
    }
}

public struct ScreenPoint: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var x: Double
    public var y: Double

    public init(
        id: UUID = UUID(),
        name: String = "Point",
        x: Double = 0,
        y: Double = 0
    ) {
        self.id = id
        self.name = name
        self.x = x
        self.y = y
    }

    public var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }

    public var coordinatesSummary: String {
        "x: \(Int(x.rounded())), y: \(Int(y.rounded()))"
    }
}

public struct ClickUnit: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: ClickUnitKind
    public var frequencyHz: Double
    public var runDurationSeconds: Double
    public var singlePoint: ScreenPoint
    public var groupPoints: [ScreenPoint]
    public var isRunning: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case frequencyHz
        case runDurationSeconds
        case singlePoint
        case groupPoints
        case isRunning
    }

    public init(
        id: UUID = UUID(),
        name: String,
        kind: ClickUnitKind,
        frequencyHz: Double,
        runDurationSeconds: Double = 0,
        singlePoint: ScreenPoint = ScreenPoint(name: "Point"),
        groupPoints: [ScreenPoint] = [],
        isRunning: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.frequencyHz = frequencyHz
        self.runDurationSeconds = runDurationSeconds
        self.singlePoint = singlePoint
        self.groupPoints = groupPoints
        self.isRunning = isRunning
        self = sanitized()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.kind = try container.decode(ClickUnitKind.self, forKey: .kind)
        self.frequencyHz = try container.decodeIfPresent(Double.self, forKey: .frequencyHz) ?? 1
        self.runDurationSeconds = try container.decodeIfPresent(Double.self, forKey: .runDurationSeconds) ?? 0
        self.singlePoint = try container.decodeIfPresent(ScreenPoint.self, forKey: .singlePoint) ?? ScreenPoint(name: "Point")
        self.groupPoints = try container.decodeIfPresent([ScreenPoint].self, forKey: .groupPoints) ?? []
        self.isRunning = try container.decodeIfPresent(Bool.self, forKey: .isRunning) ?? false
        self = sanitized()
    }

    public static func defaultSinglePoint(index: Int = 1) -> ClickUnit {
        ClickUnit(
            name: "Single Point \(index)",
            kind: .singlePoint,
            frequencyHz: 2,
            runDurationSeconds: 0,
            singlePoint: ScreenPoint(name: "Point"),
            groupPoints: []
        )
    }

    public static func defaultPointGroup(index: Int = 1) -> ClickUnit {
        ClickUnit(
            name: "Point Group \(index)",
            kind: .pointGroup,
            frequencyHz: 1,
            runDurationSeconds: 0,
            singlePoint: ScreenPoint(name: "Point"),
            groupPoints: [
                ScreenPoint(name: "Point 1"),
                ScreenPoint(name: "Point 2"),
            ]
        )
    }

    public var pointsInOrder: [ScreenPoint] {
        switch kind {
        case .singlePoint:
            return [singlePoint]
        case .pointGroup:
            return groupPoints
        }
    }

    public var pointCount: Int {
        pointsInOrder.count
    }

    public var isRunnable: Bool {
        frequencyHz > 0 && !pointsInOrder.isEmpty
    }

    public var frequencySummary: String {
        String(format: "%.2f Hz", frequencyHz)
    }

    public var runDurationSummary: String {
        guard runDurationSeconds > 0 else {
            return "No auto-stop"
        }

        return "Auto-stop after \(Int(runDurationSeconds.rounded()))s"
    }

    public var summary: String {
        switch kind {
        case .singlePoint:
            return singlePoint.coordinatesSummary
        case .pointGroup:
            return "\(groupPoints.count) points in sequence"
        }
    }

    public func sanitized() -> ClickUnit {
        var copy = self
        copy.frequencyHz = min(max(copy.frequencyHz, 0.1), 200)
        copy.runDurationSeconds = min(max(copy.runDurationSeconds, 0), 86_400)

        if copy.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            copy.name = copy.kind.defaultName
        }

        if copy.singlePoint.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            copy.singlePoint.name = "Point"
        }

        switch copy.kind {
        case .singlePoint:
            copy.groupPoints = []
        case .pointGroup:
            if copy.groupPoints.isEmpty {
                copy.groupPoints = [ScreenPoint(name: "Point 1")]
            }

            copy.groupPoints = copy.groupPoints.enumerated().map { index, point in
                var adjusted = point
                if adjusted.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    adjusted.name = "Point \(index + 1)"
                }
                return adjusted
            }
        }

        return copy
    }

    public func stoppedCopy() -> ClickUnit {
        var copy = sanitized()
        copy.isRunning = false
        return copy
    }

    public func restoredCopy() -> ClickUnit {
        var copy = stoppedCopy()
        copy.id = UUID()
        copy.singlePoint.id = UUID()
        copy.groupPoints = copy.groupPoints.enumerated().map { index, point in
            var adjusted = point
            adjusted.id = UUID()
            if adjusted.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                adjusted.name = "Point \(index + 1)"
            }
            return adjusted
        }
        return copy
    }
}

public struct HistoryRecord: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var label: String
    public var snapshot: ClickUnit

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        label: String? = nil,
        unit: ClickUnit
    ) {
        let snapshot = unit.stoppedCopy()
        let trimmedLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines)

        self.id = id
        self.createdAt = createdAt
        self.snapshot = snapshot
        self.label = (trimmedLabel?.isEmpty == false ? trimmedLabel : nil) ?? snapshot.name
    }

    public var kind: ClickUnitKind {
        snapshot.kind
    }
}

public enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case english
    case simplifiedChinese

    public var id: String { rawValue }
}

public struct AppSettings: Codable, Hashable, Sendable {
    public var startupCountdownSeconds: Int
    public var autoSaveExecutedUnitsToHistory: Bool
    public var appLanguage: AppLanguage

    enum CodingKeys: String, CodingKey {
        case startupCountdownSeconds
        case autoSaveExecutedUnitsToHistory
        case appLanguage
    }

    public init(
        startupCountdownSeconds: Int = 3,
        autoSaveExecutedUnitsToHistory: Bool = true,
        appLanguage: AppLanguage = .system
    ) {
        self.startupCountdownSeconds = AppSettings.sanitizedCountdown(startupCountdownSeconds)
        self.autoSaveExecutedUnitsToHistory = autoSaveExecutedUnitsToHistory
        self.appLanguage = appLanguage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedCountdown = try container.decodeIfPresent(Int.self, forKey: .startupCountdownSeconds) ?? 3
        self.startupCountdownSeconds = AppSettings.sanitizedCountdown(decodedCountdown)
        self.autoSaveExecutedUnitsToHistory = try container.decodeIfPresent(Bool.self, forKey: .autoSaveExecutedUnitsToHistory) ?? true
        self.appLanguage = try container.decodeIfPresent(AppLanguage.self, forKey: .appLanguage) ?? .system
    }

    public func sanitized() -> AppSettings {
        AppSettings(
            startupCountdownSeconds: startupCountdownSeconds,
            autoSaveExecutedUnitsToHistory: autoSaveExecutedUnitsToHistory,
            appLanguage: appLanguage
        )
    }

    private static func sanitizedCountdown(_ value: Int) -> Int {
        min(max(value, 0), 60)
    }
}

public struct PersistedState: Codable, Sendable {
    public var units: [ClickUnit]
    public var history: [HistoryRecord]
    public var settings: AppSettings

    enum CodingKeys: String, CodingKey {
        case units
        case history
        case settings
    }

    public init(units: [ClickUnit] = [], history: [HistoryRecord] = [], settings: AppSettings = AppSettings()) {
        self.units = units
        self.history = history
        self.settings = settings.sanitized()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.units = try container.decodeIfPresent([ClickUnit].self, forKey: .units) ?? []
        self.history = try container.decodeIfPresent([HistoryRecord].self, forKey: .history) ?? []
        self.settings = (try container.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()).sanitized()
    }
}
