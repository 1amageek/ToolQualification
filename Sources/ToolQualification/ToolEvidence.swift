import Foundation
import XcircuitePackage

public struct ToolEvidence: Sendable, Hashable, Codable {
    public var evidenceID: String
    public var kind: ToolEvidenceKind
    public var artifact: XcircuiteFileReference?
    public var qualification: ToolEvidenceQualificationSummary?
    public var checkedAt: Date?

    public init(
        evidenceID: String,
        kind: ToolEvidenceKind,
        artifact: XcircuiteFileReference? = nil,
        qualification: ToolEvidenceQualificationSummary? = nil,
        checkedAt: Date? = nil
    ) {
        self.evidenceID = evidenceID
        self.kind = kind
        self.artifact = artifact
        self.qualification = qualification
        self.checkedAt = checkedAt
    }

    private enum CodingKeys: String, CodingKey {
        case evidenceID
        case kind
        case artifact
        case qualification
        case checkedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.evidenceID = try container.decode(String.self, forKey: .evidenceID)
        self.kind = try container.decode(ToolEvidenceKind.self, forKey: .kind)
        self.artifact = try container.decodeIfPresent(
            XcircuiteFileReference.self,
            forKey: .artifact
        )
        self.qualification = try container.decodeIfPresent(
            ToolEvidenceQualificationSummary.self,
            forKey: .qualification
        )
        self.checkedAt = try Self.decodeCheckedAt(from: container)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(evidenceID, forKey: .evidenceID)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(artifact, forKey: .artifact)
        try container.encodeIfPresent(qualification, forKey: .qualification)
        if let checkedAt {
            try container.encode(Self.iso8601String(from: checkedAt), forKey: .checkedAt)
        }
    }

    private static func decodeCheckedAt(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Date? {
        guard container.contains(.checkedAt) else {
            return nil
        }
        if try container.decodeNil(forKey: .checkedAt) {
            return nil
        }
        do {
            let string = try container.decode(String.self, forKey: .checkedAt)
            if let date = iso8601Date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                forKey: .checkedAt,
                in: container,
                debugDescription: "checkedAt must be an ISO 8601 timestamp."
            )
        } catch let stringDecodingError as DecodingError {
            if case .dataCorrupted = stringDecodingError {
                throw stringDecodingError
            }
        }

        do {
            let seconds = try container.decode(Double.self, forKey: .checkedAt)
            return Date(timeIntervalSinceReferenceDate: seconds)
        } catch let numericDecodingError as DecodingError {
            if case .dataCorrupted = numericDecodingError {
                throw numericDecodingError
            }
        } catch {
            throw error
        }

        throw DecodingError.dataCorruptedError(
            forKey: .checkedAt,
            in: container,
            debugDescription: "checkedAt must be an ISO 8601 timestamp or a legacy numeric Date value."
        )
    }

    private static func iso8601Date(from string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        return formatter.string(from: date)
    }
}

public extension ToolEvidence {
    var hasPassingQualificationSupport: Bool {
        guard let qualification,
              qualification.qualified,
              qualification.failureCodes.isEmpty else {
            return false
        }

        if let artifact,
           !artifact.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if let policyID = qualification.policyID,
           !policyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return !qualification.observedMetrics.isEmpty || !qualification.observedCounts.isEmpty
    }
}
