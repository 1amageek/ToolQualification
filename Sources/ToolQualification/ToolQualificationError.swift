import Foundation

public enum ToolQualificationError: Error, LocalizedError, Equatable {
    case descriptorNotFound(String)
    case duplicateToolID(String)

    public var errorDescription: String? {
        switch self {
        case .descriptorNotFound(let toolID):
            "Tool descriptor not found: \(toolID)"
        case .duplicateToolID(let toolID):
            "Duplicate tool descriptor ID: \(toolID)"
        }
    }
}
