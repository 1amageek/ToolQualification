import Foundation

/// Single-object JSON envelope written to stderr for every CLI failure.
///
/// The envelope is serialized without a throwing encoder so a failure report
/// can never itself fail: the CLI always produces machine-readable stderr.
public struct ToolQualificationCLIDiagnosticEnvelope: Sendable, Equatable, Codable {
    public var code: String
    public var message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }

    /// Non-throwing JSON serialization of the envelope.
    public func serialized() -> String {
        "{\"code\":\"\(Self.escape(code))\",\"message\":\"\(Self.escape(message))\"}"
    }

    private static func escape(_ value: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(value.count)
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\":
                escaped.append("\\\\")
            case "\"":
                escaped.append("\\\"")
            case "\n":
                escaped.append("\\n")
            case "\r":
                escaped.append("\\r")
            case "\t":
                escaped.append("\\t")
            default:
                if scalar.value < 0x20 {
                    escaped.append(String(format: "\\u%04X", scalar.value))
                } else {
                    escaped.unicodeScalars.append(scalar)
                }
            }
        }
        return escaped
    }
}
