import Foundation

public enum ToolHealthStatus: String, Sendable, Hashable, Codable {
    case passed
    case failed
    case blocked
    case notChecked
}
