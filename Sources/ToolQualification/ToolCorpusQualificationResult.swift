import Foundation
import CircuiteFoundation

public struct ToolCorpusQualificationResult: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let resultID: String
    public let qualificationID: String
    public let toolID: String
    public let scope: ToolQualificationScope
    public let issuer: ProducerIdentity
    public let inputArtifacts: [ArtifactReference]
    public let outputArtifacts: [ArtifactReference]
    public let coverage: ToolQualificationCoverage
    public let cases: [ToolQualificationCaseOutcome]
    public let checkedAt: Date

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case resultID
        case qualificationID
        case toolID
        case scope
        case issuer
        case inputArtifacts
        case outputArtifacts
        case coverage
        case cases
        case checkedAt
    }

    public init(
        resultID: String,
        qualificationID: String,
        toolID: String,
        scope: ToolQualificationScope,
        issuer: ProducerIdentity,
        inputArtifacts: [ArtifactReference],
        outputArtifacts: [ArtifactReference],
        coverage: ToolQualificationCoverage = ToolQualificationCoverage(),
        cases: [ToolQualificationCaseOutcome],
        checkedAt: Date,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.resultID = resultID
        self.qualificationID = qualificationID
        self.toolID = toolID
        self.scope = scope
        self.issuer = issuer
        self.inputArtifacts = inputArtifacts.sorted { $0.id.rawValue < $1.id.rawValue }
        self.outputArtifacts = outputArtifacts.sorted { $0.id.rawValue < $1.id.rawValue }
        self.coverage = coverage
        self.cases = cases.sorted { $0.caseID < $1.caseID }
        self.checkedAt = checkedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        try Self.requireCurrentSchemaVersion(schemaVersion, in: container)
        self.init(
            resultID: try container.decode(String.self, forKey: .resultID),
            qualificationID: try container.decode(String.self, forKey: .qualificationID),
            toolID: try container.decode(String.self, forKey: .toolID),
            scope: try container.decode(ToolQualificationScope.self, forKey: .scope),
            issuer: try container.decode(ProducerIdentity.self, forKey: .issuer),
            inputArtifacts: try container.decode([ArtifactReference].self, forKey: .inputArtifacts),
            outputArtifacts: try container.decode([ArtifactReference].self, forKey: .outputArtifacts),
            coverage: try container.decode(ToolQualificationCoverage.self, forKey: .coverage),
            cases: try container.decode([ToolQualificationCaseOutcome].self, forKey: .cases),
            checkedAt: try container.decode(Date.self, forKey: .checkedAt),
            schemaVersion: schemaVersion
        )
    }

    private static func requireCurrentSchemaVersion(
        _ version: Int,
        in container: KeyedDecodingContainer<CodingKeys>
    ) throws {
        guard version == currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Expected corpus qualification schema version \(currentSchemaVersion)."
            )
        }
    }

    public var isStructurallyValid: Bool {
        schemaVersion == Self.currentSchemaVersion
            && !resultID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !qualificationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !toolID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && scope.isComplete
            && !inputArtifacts.isEmpty
            && inputArtifacts.allSatisfy(ToolQualificationArtifactValidation.isVerifiable)
            && ToolQualificationArtifactValidation.hasDistinctIdentities(inputArtifacts)
            && !outputArtifacts.isEmpty
            && outputArtifacts.allSatisfy(ToolQualificationArtifactValidation.isVerifiable)
            && ToolQualificationArtifactValidation.hasDistinctIdentities(outputArtifacts)
            && ToolQualificationArtifactValidation.areDisjoint(inputArtifacts, outputArtifacts)
            && coverage.isStructurallyValid
            && !cases.isEmpty
            && Set(cases.map(\.caseID)).count == cases.count
            && cases.allSatisfy(\.isStructurallyValid)
            && checkedAt.timeIntervalSinceReferenceDate.isFinite
    }

    public var isPassing: Bool {
        isStructurallyValid && cases.allSatisfy { $0.passed && $0.failureCodes.isEmpty }
    }

    public func canonicalData() throws -> Data {
        guard isStructurallyValid else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput("corpus result is not structurally valid")
        }
        let normalized = ToolCorpusQualificationResult(
            resultID: resultID,
            qualificationID: qualificationID,
            toolID: toolID,
            scope: scope,
            issuer: issuer,
            inputArtifacts: inputArtifacts,
            outputArtifacts: outputArtifacts,
            coverage: coverage,
            cases: cases.map {
            ToolQualificationCaseOutcome(
                caseID: $0.caseID,
                coverageTags: $0.coverageTags,
                comparisons: $0.comparisons
            )
            },
            checkedAt: checkedAt,
            schemaVersion: schemaVersion
        )
        return try ToolQualificationCanonicalJSON.encode(normalized)
    }

    public static func decodeCanonical(from data: Data) throws -> Self {
        let result = try ToolQualificationCanonicalJSON.decode(Self.self, from: data)
        guard result.isStructurallyValid, try result.canonicalData() == data else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput("corpus result is not canonical")
        }
        return result
    }
}
