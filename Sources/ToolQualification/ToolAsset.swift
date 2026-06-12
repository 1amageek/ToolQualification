import Foundation

public struct ToolAsset: Sendable, Hashable, Codable {
    public var path: String
    public var kind: ToolAssetKind
    public var sha256: String?

    public init(path: String, kind: ToolAssetKind, sha256: String? = nil) {
        self.path = path
        self.kind = kind
        self.sha256 = sha256
    }
}
