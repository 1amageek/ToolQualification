import Foundation

public enum ToolProcessQualificationStatus: String, Sendable, Hashable, Codable, CaseIterable {
    case unqualified
    case qualified
    case expired
    case blocked
}
