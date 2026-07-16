import Foundation
import CircuiteFoundation

public struct ToolProcessQualificationEvidence: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 4

    public let schemaVersion: Int
    public let qualificationID: String
    public let toolID: String
    public let scope: ToolQualificationScope
    public let identityArtifacts: ToolProcessQualificationArtifacts
    public let status: ToolProcessQualificationStatus
    public let corpusEvidence: [ToolEvidence]
    public let oracleEvidence: [ToolEvidence]
    public let healthEvidence: [ToolEvidence]
    public let inputArtifacts: [ArtifactReference]
    public let outputArtifacts: [ArtifactReference]
    public let qualifiedModelIDs: [String]
    public let blockers: [String]
    public let qualifiedAt: Date?
    public let expiresAt: Date?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case qualificationID
        case toolID
        case scope
        case identityArtifacts
        case status
        case corpusEvidence
        case oracleEvidence
        case healthEvidence
        case inputArtifacts
        case outputArtifacts
        case qualifiedModelIDs
        case blockers
        case qualifiedAt
        case expiresAt
    }

    init(
        qualificationID: String,
        toolID: String,
        scope: ToolQualificationScope,
        identityArtifacts: ToolProcessQualificationArtifacts,
        status: ToolProcessQualificationStatus = .unqualified,
        corpusEvidence: [ToolEvidence] = [],
        oracleEvidence: [ToolEvidence] = [],
        healthEvidence: [ToolEvidence] = [],
        inputArtifacts: [ArtifactReference] = [],
        outputArtifacts: [ArtifactReference] = [],
        qualifiedModelIDs: [String] = [],
        blockers: [String] = [],
        qualifiedAt: Date? = nil,
        expiresAt: Date? = nil,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.qualificationID = qualificationID
        self.toolID = toolID
        self.scope = scope
        self.identityArtifacts = identityArtifacts
        self.status = status
        self.corpusEvidence = Self.sortedEvidence(corpusEvidence)
        self.oracleEvidence = Self.sortedEvidence(oracleEvidence)
        self.healthEvidence = Self.sortedEvidence(healthEvidence)
        self.inputArtifacts = Self.sortedArtifacts(inputArtifacts)
        self.outputArtifacts = Self.sortedArtifacts(outputArtifacts)
        self.qualifiedModelIDs = Self.sortedUnique(qualifiedModelIDs)
        self.blockers = Self.sortedUnique(blockers)
        self.qualifiedAt = qualifiedAt
        self.expiresAt = expiresAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Expected process qualification evidence schema version \(Self.currentSchemaVersion)."
            )
        }
        self.init(
            qualificationID: try container.decode(String.self, forKey: .qualificationID),
            toolID: try container.decode(String.self, forKey: .toolID),
            scope: try container.decode(ToolQualificationScope.self, forKey: .scope),
            identityArtifacts: try container.decode(ToolProcessQualificationArtifacts.self, forKey: .identityArtifacts),
            status: try container.decode(ToolProcessQualificationStatus.self, forKey: .status),
            corpusEvidence: try container.decode([ToolEvidence].self, forKey: .corpusEvidence),
            oracleEvidence: try container.decode([ToolEvidence].self, forKey: .oracleEvidence),
            healthEvidence: try container.decode([ToolEvidence].self, forKey: .healthEvidence),
            inputArtifacts: try container.decode([ArtifactReference].self, forKey: .inputArtifacts),
            outputArtifacts: try container.decode([ArtifactReference].self, forKey: .outputArtifacts),
            qualifiedModelIDs: try container.decode([String].self, forKey: .qualifiedModelIDs),
            blockers: try container.decode([String].self, forKey: .blockers),
            qualifiedAt: try container.decodeIfPresent(Date.self, forKey: .qualifiedAt),
            expiresAt: try container.decodeIfPresent(Date.self, forKey: .expiresAt),
            schemaVersion: schemaVersion
        )
    }

    public var corpusEvidenceIDs: [String] { corpusEvidence.map(\.evidenceID) }
    public var oracleEvidenceIDs: [String] { oracleEvidence.map(\.evidenceID) }
    public var healthEvidenceIDs: [String] { healthEvidence.map(\.evidenceID) }
    public var evidenceArtifactIDs: [String] { evidenceArtifacts.map { $0.id.rawValue } }
    public var evidenceArtifacts: [ArtifactReference] {
        Self.sortedArtifacts((corpusEvidence + oracleEvidence + healthEvidence).compactMap(\.artifact))
    }
    public var hasIndependentOracleEvidence: Bool {
        guard scope.isCompleteForProduction else { return false }
        let tool = identityArtifacts.toolExecutable
        let oracle = identityArtifacts.oracleExecutable
        return identityArtifactsMatchScope
            && tool.digest != oracle.digest
            && !oracleEvidence.isEmpty
            && oracleEvidence.allSatisfy { $0.artifact != nil }
    }

    public var identityArtifactsMatchScope: Bool {
        guard let pdkDigest = scope.pdkDigest,
              let oracleScope = scope.oracle else {
            return false
        }
        let tool = identityArtifacts.toolExecutable
        let oracle = identityArtifacts.oracleExecutable
        return tool.sha256.caseInsensitiveCompare(scope.binaryDigest) == .orderedSame
            && identityArtifacts.processProfile.sha256.caseInsensitiveCompare(scope.processProfileDigest) == .orderedSame
            && identityArtifacts.pdk.sha256.caseInsensitiveCompare(pdkDigest) == .orderedSame
            && identityArtifacts.ruleDeck.sha256.caseInsensitiveCompare(scope.deckDigest) == .orderedSame
            && oracle.sha256.caseInsensitiveCompare(oracleScope.binaryDigest) == .orderedSame
            && tool.producer?.kind == .tool
            && tool.producer?.identifier == scope.implementationID
            && tool.producer?.version == scope.toolVersion
            && oracle.producer?.kind == .tool
            && oracle.producer?.identifier == oracleScope.implementationID
            && oracle.producer?.version == oracleScope.version
    }

    public var isStructurallyValid: Bool {
        let evidenceGroups: [(ToolEvidenceKind, [ToolEvidence])] = [
            (.corpus, corpusEvidence),
            (.oracle, oracleEvidence),
            (.healthCheck, healthEvidence),
        ]
        let allEvidence = evidenceGroups.flatMap(\.1)
        let retainedArtifacts = Set(evidenceArtifacts)
        let evidenceIDs = allEvidence.map(\.evidenceID)
        return schemaVersion == Self.currentSchemaVersion
            && !qualificationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !toolID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && scope.isCompleteForProduction
            && hasIndependentOracleEvidence
            && identityArtifacts.all.count == Set(identityArtifacts.all).count
            && identityArtifacts.all.allSatisfy(Self.isVerifiableArtifact)
            && evidenceGroups.allSatisfy { kind, evidence in
                !evidence.isEmpty && evidence.allSatisfy {
                    $0.kind == kind
                        && !$0.evidenceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && $0.hasVerifiableArtifactBinding
                        && $0.artifact.map(retainedArtifacts.contains) == true
                }
            }
            && Set(evidenceIDs).count == evidenceIDs.count
            && !evidenceArtifacts.isEmpty
            && evidenceArtifacts.allSatisfy(Self.isVerifiableArtifact)
            && !inputArtifacts.isEmpty
            && inputArtifacts.allSatisfy(Self.isVerifiableArtifact)
            && !outputArtifacts.isEmpty
            && outputArtifacts.allSatisfy(Self.isVerifiableArtifact)
    }

    public func isQualified(at date: Date, requirePDKScope: Bool = true) -> Bool {
        status == .qualified
            && isStructurallyValid
            && (!requirePDKScope || scope.isCompleteForPDK)
            && blockers.isEmpty
            && isFresh(at: date)
    }

    public func isFresh(at date: Date) -> Bool {
        guard let qualifiedAt, let expiresAt else {
            return false
        }
        return qualifiedAt <= date && date < expiresAt
    }

    public func canonicalData() throws -> Data {
        guard schemaVersion == Self.currentSchemaVersion, isStructurallyValid else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput(
                "process qualification evidence is not structurally valid"
            )
        }
        let normalized = ToolProcessQualificationEvidence(
            qualificationID: qualificationID,
            toolID: toolID,
            scope: scope,
            identityArtifacts: identityArtifacts,
            status: status,
            corpusEvidence: Self.normalizedEvidence(corpusEvidence),
            oracleEvidence: Self.normalizedEvidence(oracleEvidence),
            healthEvidence: Self.normalizedEvidence(healthEvidence),
            inputArtifacts: Self.sortedArtifacts(inputArtifacts),
            outputArtifacts: Self.sortedArtifacts(outputArtifacts),
            qualifiedModelIDs: qualifiedModelIDs.sorted(),
            blockers: blockers.sorted(),
            qualifiedAt: qualifiedAt,
            expiresAt: expiresAt,
            schemaVersion: schemaVersion
        )
        return try ToolQualificationCanonicalJSON.encode(normalized)
    }

    public static func decodeCanonical(from data: Data) throws -> Self {
        let evidence = try ToolQualificationCanonicalJSON.decode(Self.self, from: data)
        guard evidence.schemaVersion == Self.currentSchemaVersion,
              evidence.isStructurallyValid,
              try evidence.canonicalData() == data else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput(
                "process qualification evidence is not structurally valid"
            )
        }
        return evidence
    }

    private static func isVerifiableArtifact(_ artifact: ArtifactReference) -> Bool {
        artifact.locator.location.storage == .workspaceRelative
            && !artifact.locator.location.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && artifact.digest.algorithm == .sha256
            && artifact.digest.hexadecimalValue.utf8.count == 64
            && artifact.byteCount > 0
    }

    private static func sortedUnique(_ values: [String]) -> [String] {
        Array(Set(values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })).sorted()
    }

    private static func sortedEvidence(_ evidence: [ToolEvidence]) -> [ToolEvidence] {
        evidence.sorted { $0.evidenceID < $1.evidenceID }
    }

    private static func normalizedEvidence(_ evidence: [ToolEvidence]) -> [ToolEvidence] {
        evidence.sorted { $0.evidenceID < $1.evidenceID }
    }

    private static func sortedArtifacts(_ artifacts: [ArtifactReference]) -> [ArtifactReference] {
        artifacts.sorted { $0.id.rawValue < $1.id.rawValue }
    }
}
