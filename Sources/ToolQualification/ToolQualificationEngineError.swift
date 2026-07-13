import Foundation

public enum ToolQualificationEngineError: Error, Sendable, Equatable, Hashable, LocalizedError {
    case invalidDiagnosticCode(String)

    public var errorDescription: String? {
        switch self {
        case .invalidDiagnosticCode(let code):
            "Tool qualification diagnostic code cannot be represented by CircuiteFoundation: \(code)"
        }
    }
}
