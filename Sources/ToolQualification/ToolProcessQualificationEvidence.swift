import Foundation

public struct ToolProcessQualificationEvidence: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var qualificationID: String
    public var toolID: String
    public var scope: ToolQualificationScope
    public var status: ToolProcessQualificationStatus
    public var corpusEvidenceIDs: [String]
    public var oracleEvidenceIDs: [String]
    public var healthEvidenceIDs: [String]
    public var approvalEvidenceIDs: [String]
    public var evidenceArtifactIDs: [String]
    public var independenceVerified: Bool
    public var blockers: [String]
    public var qualifiedAt: Date?
    public var expiresAt: Date?

    public init(
        qualificationID: String,
        toolID: String,
        scope: ToolQualificationScope,
        status: ToolProcessQualificationStatus = .unqualified,
        corpusEvidenceIDs: [String] = [],
        oracleEvidenceIDs: [String] = [],
        healthEvidenceIDs: [String] = [],
        approvalEvidenceIDs: [String] = [],
        evidenceArtifactIDs: [String] = [],
        independenceVerified: Bool = false,
        blockers: [String] = [],
        qualifiedAt: Date? = nil,
        expiresAt: Date? = nil,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.qualificationID = qualificationID
        self.toolID = toolID
        self.scope = scope
        self.status = status
        self.corpusEvidenceIDs = Self.sortedUnique(corpusEvidenceIDs)
        self.oracleEvidenceIDs = Self.sortedUnique(oracleEvidenceIDs)
        self.healthEvidenceIDs = Self.sortedUnique(healthEvidenceIDs)
        self.approvalEvidenceIDs = Self.sortedUnique(approvalEvidenceIDs)
        self.evidenceArtifactIDs = Self.sortedUnique(evidenceArtifactIDs)
        self.independenceVerified = independenceVerified
        self.blockers = Self.sortedUnique(blockers)
        self.qualifiedAt = qualifiedAt
        self.expiresAt = expiresAt
    }

    public var isStructurallyValid: Bool {
        schemaVersion == Self.currentSchemaVersion
            && !qualificationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !toolID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && scope.isComplete
            && !corpusEvidenceIDs.isEmpty
            && !oracleEvidenceIDs.isEmpty
            && !healthEvidenceIDs.isEmpty
            && !approvalEvidenceIDs.isEmpty
            && !evidenceArtifactIDs.isEmpty
    }

    public func isQualified(at date: Date, requirePDKScope: Bool = false) -> Bool {
        status == .qualified
            && isStructurallyValid
            && (!requirePDKScope || scope.isCompleteForPDK)
            && independenceVerified
            && blockers.isEmpty
            && isFresh(at: date)
    }

    public func isFresh(at date: Date) -> Bool {
        guard let qualifiedAt, let expiresAt else {
            return false
        }
        return qualifiedAt <= date && date < expiresAt
    }

    public func summary(policyID: String? = nil) -> ToolEvidenceQualificationSummary {
        ToolEvidenceQualificationSummary(
            qualified: status == .qualified,
            policyID: policyID,
            observedCounts: [
                "corpusEvidenceCount": corpusEvidenceIDs.count,
                "oracleEvidenceCount": oracleEvidenceIDs.count,
                "healthEvidenceCount": healthEvidenceIDs.count,
                "approvalEvidenceCount": approvalEvidenceIDs.count,
            ],
            failureCodes: blockers,
            scope: scope,
            qualificationID: qualificationID,
            independenceVerified: independenceVerified
        )
    }

    private static func sortedUnique(_ values: [String]) -> [String] {
        Array(Set(values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })).sorted()
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case qualificationID
        case toolID
        case scope
        case status
        case corpusEvidenceIDs
        case oracleEvidenceIDs
        case healthEvidenceIDs
        case approvalEvidenceIDs
        case evidenceArtifactIDs
        case independenceVerified
        case blockers
        case qualifiedAt
        case expiresAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        qualificationID = try container.decode(String.self, forKey: .qualificationID)
        toolID = try container.decode(String.self, forKey: .toolID)
        scope = try container.decode(ToolQualificationScope.self, forKey: .scope)
        status = try container.decode(ToolProcessQualificationStatus.self, forKey: .status)
        corpusEvidenceIDs = try container.decode([String].self, forKey: .corpusEvidenceIDs)
        oracleEvidenceIDs = try container.decode([String].self, forKey: .oracleEvidenceIDs)
        healthEvidenceIDs = try container.decode([String].self, forKey: .healthEvidenceIDs)
        approvalEvidenceIDs = try container.decode([String].self, forKey: .approvalEvidenceIDs)
        evidenceArtifactIDs = try container.decode([String].self, forKey: .evidenceArtifactIDs)
        independenceVerified = try container.decode(Bool.self, forKey: .independenceVerified)
        blockers = try container.decode([String].self, forKey: .blockers)
        qualifiedAt = try Self.decodeDate(from: container, forKey: .qualifiedAt)
        expiresAt = try Self.decodeDate(from: container, forKey: .expiresAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(qualificationID, forKey: .qualificationID)
        try container.encode(toolID, forKey: .toolID)
        try container.encode(scope, forKey: .scope)
        try container.encode(status, forKey: .status)
        try container.encode(corpusEvidenceIDs, forKey: .corpusEvidenceIDs)
        try container.encode(oracleEvidenceIDs, forKey: .oracleEvidenceIDs)
        try container.encode(healthEvidenceIDs, forKey: .healthEvidenceIDs)
        try container.encode(approvalEvidenceIDs, forKey: .approvalEvidenceIDs)
        try container.encode(evidenceArtifactIDs, forKey: .evidenceArtifactIDs)
        try container.encode(independenceVerified, forKey: .independenceVerified)
        try container.encode(blockers, forKey: .blockers)
        try Self.encodeDate(qualifiedAt, into: &container, forKey: .qualifiedAt)
        try Self.encodeDate(expiresAt, into: &container, forKey: .expiresAt)
    }

    private static func decodeDate<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) throws -> Date? {
        guard try !container.decodeNil(forKey: key) else {
            return nil
        }
        do {
            let string = try container.decode(String.self, forKey: key)
            guard let date = iso8601Formatter.date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    forKey: key,
                    in: container,
                    debugDescription: "date must be a valid ISO-8601 timestamp"
                )
            }
            return date
        } catch DecodingError.typeMismatch {
            let seconds = try container.decode(Double.self, forKey: key)
            return Date(timeIntervalSinceReferenceDate: seconds)
        }
    }

    private static func encodeDate<Key: CodingKey>(
        _ date: Date?,
        into container: inout KeyedEncodingContainer<Key>,
        forKey key: Key
    ) throws {
        guard let date else {
            try container.encodeNil(forKey: key)
            return
        }
        try container.encode(iso8601Formatter.string(from: date), forKey: key)
    }

    private static var iso8601Formatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
