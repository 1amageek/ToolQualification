import Foundation

/// Sequential reader over CLI arguments with typed failures for missing or
/// malformed option values.
struct ToolQualificationCLIArgumentCursor: Sendable {
    private let arguments: [String]
    private var index = 0

    init(arguments: [String]) {
        self.arguments = arguments
    }

    mutating func next() -> String? {
        guard index < arguments.count else { return nil }
        let value = arguments[index]
        index += 1
        return value
    }

    mutating func requireValue(for option: String) throws -> String {
        guard let value = next(), !value.isEmpty, !value.hasPrefix("--") else {
            throw ToolQualificationCLIError.invalidArguments("Missing value for \(option)")
        }
        return value
    }
}
