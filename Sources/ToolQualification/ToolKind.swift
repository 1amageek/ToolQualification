import Foundation

public enum ToolKind: String, Sendable, Hashable, Codable {
    case simulation
    case layout
    case drc
    case lvs
    case pex
    case maskIO
    case planning
    case reporting
}
