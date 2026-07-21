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

    public var isStructurallyValid: Bool {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        guard let sha256 else {
            return true
        }
        return sha256.utf8.count == 64 && sha256.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57)
                || (byte >= 65 && byte <= 70)
                || (byte >= 97 && byte <= 102)
        }
    }
}
