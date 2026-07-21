import Foundation

public enum ToolQualificationError: Error, LocalizedError, Equatable {
    case invalidToolID(String)
    case structurallyInvalidDescriptor(String)
    case descriptorNotFound(String)
    case duplicateToolID(String)

    public var errorDescription: String? {
        switch self {
        case .invalidToolID(let toolID):
            "Invalid tool descriptor ID: \(toolID)"
        case .structurallyInvalidDescriptor(let toolID):
            "Tool descriptor is structurally invalid: \(toolID)"
        case .descriptorNotFound(let toolID):
            "Tool descriptor not found: \(toolID)"
        case .duplicateToolID(let toolID):
            "Duplicate tool descriptor ID: \(toolID)"
        }
    }
}
