import Foundation

public enum ToolAssetKind: String, Sendable, Hashable, Codable {
    case executable
    case library
    case pdk
    case ruleDeck
    case technology
    case model
    case fixture
    case other
}
