import Foundation
import XcircuitePackage

public struct ToolProcessQualificationEvidenceBuildRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var qualificationID: String
    public var toolID: String
    public var scope: ToolQualificationScope
    public var corpusEvidence: [ToolEvidence]
    public var oracleEvidence: [ToolEvidence]
    public var healthEvidence: [ToolEvidence]
    public var approvalEvidence: [ToolEvidence]
    public var evidenceArtifacts: [XcircuiteFileReference]
    public var qualifiedModelIDs: [String]
    public var independenceVerified: Bool
    public var requirePDKScope: Bool
    public var qualifiedAt: Date
    public var expiresAt: Date

    public init(
        qualificationID: String,
        toolID: String,
        scope: ToolQualificationScope,
        corpusEvidence: [ToolEvidence],
        oracleEvidence: [ToolEvidence],
        healthEvidence: [ToolEvidence],
        approvalEvidence: [ToolEvidence],
        evidenceArtifacts: [XcircuiteFileReference],
        qualifiedModelIDs: [String] = [],
        independenceVerified: Bool,
        requirePDKScope: Bool = true,
        qualifiedAt: Date,
        expiresAt: Date,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.qualificationID = qualificationID
        self.toolID = toolID
        self.scope = scope
        self.corpusEvidence = corpusEvidence
        self.oracleEvidence = oracleEvidence
        self.healthEvidence = healthEvidence
        self.approvalEvidence = approvalEvidence
        self.evidenceArtifacts = evidenceArtifacts
        self.qualifiedModelIDs = Self.sortedUnique(qualifiedModelIDs)
        self.independenceVerified = independenceVerified
        self.requirePDKScope = requirePDKScope
        self.qualifiedAt = qualifiedAt
        self.expiresAt = expiresAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case qualificationID
        case toolID
        case scope
        case corpusEvidence
        case oracleEvidence
        case healthEvidence
        case approvalEvidence
        case evidenceArtifacts
        case qualifiedModelIDs
        case independenceVerified
        case requirePDKScope
        case qualifiedAt
        case expiresAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        qualificationID = try container.decode(String.self, forKey: .qualificationID)
        toolID = try container.decode(String.self, forKey: .toolID)
        scope = try container.decode(ToolQualificationScope.self, forKey: .scope)
        corpusEvidence = try container.decode([ToolEvidence].self, forKey: .corpusEvidence)
        oracleEvidence = try container.decode([ToolEvidence].self, forKey: .oracleEvidence)
        healthEvidence = try container.decode([ToolEvidence].self, forKey: .healthEvidence)
        approvalEvidence = try container.decode([ToolEvidence].self, forKey: .approvalEvidence)
        evidenceArtifacts = try container.decode([XcircuiteFileReference].self, forKey: .evidenceArtifacts)
        qualifiedModelIDs = Self.sortedUnique(
            try container.decodeIfPresent([String].self, forKey: .qualifiedModelIDs) ?? []
        )
        independenceVerified = try container.decode(Bool.self, forKey: .independenceVerified)
        requirePDKScope = try container.decodeIfPresent(Bool.self, forKey: .requirePDKScope) ?? true
        qualifiedAt = try Self.decodeDate(from: container, forKey: .qualifiedAt)
        expiresAt = try Self.decodeDate(from: container, forKey: .expiresAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(qualificationID, forKey: .qualificationID)
        try container.encode(toolID, forKey: .toolID)
        try container.encode(scope, forKey: .scope)
        try container.encode(corpusEvidence, forKey: .corpusEvidence)
        try container.encode(oracleEvidence, forKey: .oracleEvidence)
        try container.encode(healthEvidence, forKey: .healthEvidence)
        try container.encode(approvalEvidence, forKey: .approvalEvidence)
        try container.encode(evidenceArtifacts, forKey: .evidenceArtifacts)
        try container.encode(qualifiedModelIDs, forKey: .qualifiedModelIDs)
        try container.encode(independenceVerified, forKey: .independenceVerified)
        try container.encode(requirePDKScope, forKey: .requirePDKScope)
        try container.encode(Self.iso8601String(from: qualifiedAt), forKey: .qualifiedAt)
        try container.encode(Self.iso8601String(from: expiresAt), forKey: .expiresAt)
    }

    private static func decodeDate<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) throws -> Date {
        do {
            let string = try container.decode(String.self, forKey: key)
            guard let date = iso8601Date(from: string) else {
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

    private static func iso8601Date(from string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func sortedUnique(_ values: [String]) -> [String] {
        Array(Set(values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })).sorted()
    }
}
