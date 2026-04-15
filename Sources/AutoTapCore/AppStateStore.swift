import Foundation

public final class AppStateStore {
    public let stateURL: URL

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger = AutoTapLog.logger(category: "StateStore")

    public init(fileManager: FileManager = .default, stateURL: URL? = nil) {
        self.fileManager = fileManager

        if let stateURL {
            self.stateURL = stateURL
        } else {
            let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory())
                    .appendingPathComponent("Library", isDirectory: true)
                    .appendingPathComponent("Application Support", isDirectory: true)

            self.stateURL = baseDirectory
                .appendingPathComponent("AutoTap", isDirectory: true)
                .appendingPathComponent("state.json", isDirectory: false)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public static func defaultState() -> PersistedState {
        PersistedState(
            units: [
                ClickUnit.defaultSinglePoint(index: 1),
                ClickUnit.defaultPointGroup(index: 1),
            ],
            history: []
        )
    }

    public func load() -> PersistedState {
        guard fileManager.fileExists(atPath: stateURL.path) else {
            logger.notice("No persisted state found at \(stateURL.path). Using defaults.")
            return Self.defaultState()
        }

        do {
            let data = try Data(contentsOf: stateURL)
            let decoded = try decoder.decode(PersistedState.self, from: data)
            logger.notice("Loaded persisted state from \(stateURL.path) with \(decoded.units.count) units and \(decoded.history.count) history records.")
            return decoded
        } catch {
            logger.error("Failed to load persisted state from \(stateURL.path): \(error.localizedDescription). Using defaults.")
            return Self.defaultState()
        }
    }

    public func save(_ state: PersistedState) throws {
        do {
            let directoryURL = stateURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            let data = try encoder.encode(state)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            logger.error("Failed to save state to \(stateURL.path): \(error.localizedDescription).")
            throw error
        }
    }
}
