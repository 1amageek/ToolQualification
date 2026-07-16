import CircuiteFoundation
import Foundation

public struct ToolEvidence: Sendable, Hashable, Codable {
    public let evidenceID: String
    public let kind: ToolEvidenceKind
    public let artifact: ArtifactReference?
    public let checkedAt: Date?

    public init(
        evidenceID: String,
        kind: ToolEvidenceKind,
        artifact: ArtifactReference? = nil,
        checkedAt: Date? = nil
    ) {
        self.evidenceID = evidenceID
        self.kind = kind
        self.artifact = artifact
        self.checkedAt = checkedAt
    }

    private enum CodingKeys: String, CodingKey {
        case evidenceID
        case kind
        case artifact
        case checkedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        evidenceID = try container.decode(String.self, forKey: .evidenceID)
        kind = try container.decode(ToolEvidenceKind.self, forKey: .kind)
        artifact = try container.decodeIfPresent(ArtifactReference.self, forKey: .artifact)
        if container.contains(.checkedAt), try !container.decodeNil(forKey: .checkedAt) {
            let string = try container.decode(String.self, forKey: .checkedAt)
            guard let date = Self.iso8601Date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .checkedAt,
                    in: container,
                    debugDescription: "checkedAt must be an ISO 8601 timestamp"
                )
            }
            checkedAt = date
        } else {
            checkedAt = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(evidenceID, forKey: .evidenceID)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(artifact, forKey: .artifact)
        if let checkedAt {
            try container.encode(Self.iso8601String(from: checkedAt), forKey: .checkedAt)
        }
    }

    public var hasVerifiableArtifactBinding: Bool {
        guard let artifact else { return false }
        return artifact.locator.location.storage == .workspaceRelative
            && !artifact.locator.location.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && artifact.digest.algorithm == .sha256
            && artifact.digest.hexadecimalValue.utf8.count == 64
            && artifact.byteCount > 0
    }

    private static func iso8601Date(from string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
