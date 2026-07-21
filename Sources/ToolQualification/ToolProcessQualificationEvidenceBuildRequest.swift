import Foundation
import CircuiteFoundation

public struct ToolProcessQualificationEvidenceBuildRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 6

    public var schemaVersion: Int
    public var qualificationID: String
    public var toolID: String
    public var scope: ToolQualificationScope
    public var identityArtifacts: ToolProcessQualificationArtifacts
    public var corpusResultArtifacts: [ArtifactReference]
    public var oracleResultArtifacts: [ArtifactReference]
    public var healthResultArtifacts: [ArtifactReference]
    public var inputArtifacts: [ArtifactReference]
    public var outputArtifacts: [ArtifactReference]
    public var qualifiedModelIDs: [String]
    public var requiredOperatingCornerIDs: [String]
    public var requirePDKScope: Bool
    public var qualifiedAt: Date
    public var expiresAt: Date

    public init(
        qualificationID: String,
        toolID: String,
        scope: ToolQualificationScope,
        identityArtifacts: ToolProcessQualificationArtifacts,
        corpusResultArtifacts: [ArtifactReference],
        oracleResultArtifacts: [ArtifactReference],
        healthResultArtifacts: [ArtifactReference],
        inputArtifacts: [ArtifactReference] = [],
        outputArtifacts: [ArtifactReference] = [],
        qualifiedModelIDs: [String] = [],
        requiredOperatingCornerIDs: [String] = [],
        requirePDKScope: Bool = true,
        qualifiedAt: Date,
        expiresAt: Date,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.qualificationID = qualificationID
        self.toolID = toolID
        self.scope = scope
        self.identityArtifacts = identityArtifacts
        self.corpusResultArtifacts = corpusResultArtifacts
        self.oracleResultArtifacts = oracleResultArtifacts
        self.healthResultArtifacts = healthResultArtifacts
        self.inputArtifacts = inputArtifacts
        self.outputArtifacts = outputArtifacts
        self.qualifiedModelIDs = Self.sortedUnique(qualifiedModelIDs)
        self.requiredOperatingCornerIDs = Self.sortedUnique(requiredOperatingCornerIDs)
        self.requirePDKScope = requirePDKScope
        self.qualifiedAt = qualifiedAt
        self.expiresAt = expiresAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case qualificationID
        case toolID
        case scope
        case identityArtifacts
        case corpusResultArtifacts
        case oracleResultArtifacts
        case healthResultArtifacts
        case inputArtifacts
        case outputArtifacts
        case qualifiedModelIDs
        case requiredOperatingCornerIDs
        case requirePDKScope
        case qualifiedAt
        case expiresAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Expected process qualification build-request schema version \(Self.currentSchemaVersion)."
            )
        }
        qualificationID = try container.decode(String.self, forKey: .qualificationID)
        toolID = try container.decode(String.self, forKey: .toolID)
        scope = try container.decode(ToolQualificationScope.self, forKey: .scope)
        identityArtifacts = try container.decode(ToolProcessQualificationArtifacts.self, forKey: .identityArtifacts)
        corpusResultArtifacts = try container.decode([ArtifactReference].self, forKey: .corpusResultArtifacts)
        oracleResultArtifacts = try container.decode([ArtifactReference].self, forKey: .oracleResultArtifacts)
        healthResultArtifacts = try container.decode([ArtifactReference].self, forKey: .healthResultArtifacts)
        inputArtifacts = try container.decode([ArtifactReference].self, forKey: .inputArtifacts)
        outputArtifacts = try container.decode([ArtifactReference].self, forKey: .outputArtifacts)
        qualifiedModelIDs = Self.sortedUnique(
            try container.decode([String].self, forKey: .qualifiedModelIDs)
        )
        requiredOperatingCornerIDs = Self.sortedUnique(
            try container.decode([String].self, forKey: .requiredOperatingCornerIDs)
        )
        requirePDKScope = try container.decode(Bool.self, forKey: .requirePDKScope)
        qualifiedAt = try Self.decodeDate(from: container, forKey: .qualifiedAt)
        expiresAt = try Self.decodeDate(from: container, forKey: .expiresAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(qualificationID, forKey: .qualificationID)
        try container.encode(toolID, forKey: .toolID)
        try container.encode(scope, forKey: .scope)
        try container.encode(identityArtifacts, forKey: .identityArtifacts)
        try container.encode(corpusResultArtifacts, forKey: .corpusResultArtifacts)
        try container.encode(oracleResultArtifacts, forKey: .oracleResultArtifacts)
        try container.encode(healthResultArtifacts, forKey: .healthResultArtifacts)
        try container.encode(inputArtifacts, forKey: .inputArtifacts)
        try container.encode(outputArtifacts, forKey: .outputArtifacts)
        try container.encode(qualifiedModelIDs, forKey: .qualifiedModelIDs)
        try container.encode(requiredOperatingCornerIDs, forKey: .requiredOperatingCornerIDs)
        try container.encode(requirePDKScope, forKey: .requirePDKScope)
        try container.encode(Self.iso8601String(from: qualifiedAt), forKey: .qualifiedAt)
        try container.encode(Self.iso8601String(from: expiresAt), forKey: .expiresAt)
    }

    private static func decodeDate<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) throws -> Date {
        let string = try container.decode(String.self, forKey: key)
        guard let date = iso8601Date(from: string) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "date must be a valid ISO-8601 timestamp"
            )
        }
        return date
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

    public var evidenceArtifacts: [ArtifactReference] {
        (corpusResultArtifacts + oracleResultArtifacts + healthResultArtifacts)
            .sorted { $0.id.rawValue < $1.id.rawValue }
    }
}
