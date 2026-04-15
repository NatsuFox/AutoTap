import Foundation

public struct AutoTapLog: Sendable {
    public let category: String

    public static func logger(category: String) -> AutoTapLog {
        AutoTapLog(category: category)
    }

    public func debug(_ message: @autoclosure () -> String) {
        emit(level: "DEBUG", message())
    }

    public func info(_ message: @autoclosure () -> String) {
        emit(level: "INFO", message())
    }

    public func notice(_ message: @autoclosure () -> String) {
        emit(level: "NOTICE", message())
    }

    public func error(_ message: @autoclosure () -> String) {
        emit(level: "ERROR", message())
    }

    private func emit(level: String, _ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        fputs("[\(stamp)] [AutoTap] [\(level)] [\(category)] \(message)\n", stderr)
        fflush(stderr)
    }
}
