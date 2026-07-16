import Foundation

public struct ToolOracleQualificationScope: Sendable, Hashable, Codable {
    public var implementationID: String
    public var version: String
    public var binaryDigest: String

    public init(
        implementationID: String,
        version: String,
        binaryDigest: String
    ) {
        self.implementationID = implementationID
        self.version = version
        self.binaryDigest = binaryDigest.lowercased()
    }

    public var isComplete: Bool {
        !implementationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && Self.isSHA256(binaryDigest)
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57)
                || (byte >= 65 && byte <= 70)
                || (byte >= 97 && byte <= 102)
        }
    }
}
