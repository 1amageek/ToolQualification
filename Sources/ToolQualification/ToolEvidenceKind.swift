import Foundation

public enum ToolEvidenceKind: String, Sendable, Hashable, Codable {
    case smoke
    case corpus
    case oracle
    case healthCheck
    case productionApproval
}
