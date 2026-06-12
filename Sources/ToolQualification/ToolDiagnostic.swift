import Foundation

public struct ToolDiagnostic: Sendable, Hashable, Codable {
    public var severity: ToolDiagnosticSeverity
    public var code: String
    public var message: String

    public init(severity: ToolDiagnosticSeverity, code: String, message: String) {
        self.severity = severity
        self.code = code
        self.message = message
    }
}
