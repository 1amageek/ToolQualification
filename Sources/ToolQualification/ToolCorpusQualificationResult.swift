import Foundation
import CircuiteFoundation

public struct ToolCorpusQualificationResult: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let resultID: String
    public let qualificationID: String
    public let toolID: String
    public let scope: ToolQualificationScope
    public let issuer: ProducerIdentity
    public let inputArtifacts: [ArtifactReference]
    public let outputArtifacts: [ArtifactReference]
    public let cases: [ToolQualificationCaseOutcome]
    public let checkedAt: Date

    public init(
        resultID: String,
        qualificationID: String,
        toolID: String,
        scope: ToolQualificationScope,
        issuer: ProducerIdentity,
        inputArtifacts: [ArtifactReference],
        outputArtifacts: [ArtifactReference],
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
        self.cases = cases.sorted { $0.caseID < $1.caseID }
        self.checkedAt = checkedAt
    }

    public var isStructurallyValid: Bool {
        schemaVersion == Self.currentSchemaVersion
            && !resultID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !qualificationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !toolID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && scope.isComplete
            && !inputArtifacts.isEmpty
            && !outputArtifacts.isEmpty
            && !cases.isEmpty
            && Set(cases.map(\.caseID)).count == cases.count
            && cases.allSatisfy(\.isStructurallyValid)
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
