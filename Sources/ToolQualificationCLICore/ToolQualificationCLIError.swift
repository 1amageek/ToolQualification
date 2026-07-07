import Foundation

/// Typed failures raised by the headless CLI before or during command execution.
///
/// Every case maps to a stable machine-readable diagnostic code so callers can
/// branch on `code` without parsing prose. All CLI failures exit with code 1.
public enum ToolQualificationCLIError: Error, Sendable, Equatable {
    case invalidArguments(String)
    case unreadableFile(path: String, reason: String)
    case invalidJSON(path: String, reason: String)
    case internalError(String)

    /// Stable diagnostic code emitted in the stderr JSON envelope.
    public var code: String {
        switch self {
        case .invalidArguments:
            "toolqualification.cli.invalid-arguments"
        case .unreadableFile:
            "toolqualification.cli.unreadable-file"
        case .invalidJSON:
            "toolqualification.cli.invalid-json"
        case .internalError:
            "toolqualification.cli.internal-error"
        }
    }

    /// Human-readable failure description emitted in the stderr JSON envelope.
    public var message: String {
        switch self {
        case .invalidArguments(let details):
            details
        case .unreadableFile(let path, let reason):
            "Cannot read file at \(path): \(reason)"
        case .invalidJSON(let path, let reason):
            "File at \(path) does not decode as the expected JSON model: \(reason)"
        case .internalError(let details):
            "Internal CLI failure: \(details)"
        }
    }
}
