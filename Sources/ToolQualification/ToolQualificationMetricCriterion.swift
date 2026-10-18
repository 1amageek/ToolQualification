import CircuiteFoundation
import Foundation

/// A requirement-owned acceptance rule. Nil referenceValue is only for oracle agreement.
public struct ToolQualificationMetricCriterion: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1
    public let schemaVersion: Int
    public let purpose: ToolQualificationAssessmentPurpose
    public let metricDefinitionArtifact: ArtifactReference
    public let requirementArtifact: ArtifactReference
    public let referenceArtifacts: [ArtifactReference]
    public let referenceValue: Double?
    public let comparisonRule: ToolQualificationComparisonRule

    public init(purpose: ToolQualificationAssessmentPurpose,
                metricDefinitionArtifact: ArtifactReference, requirementArtifact: ArtifactReference,
                referenceArtifacts: [ArtifactReference] = [], referenceValue: Double?,
                comparisonRule: ToolQualificationComparisonRule,
                schemaVersion: Int = Self.currentSchemaVersion) {
        self.schemaVersion = schemaVersion
        self.purpose = purpose
        self.metricDefinitionArtifact = metricDefinitionArtifact
        self.requirementArtifact = requirementArtifact
        self.referenceArtifacts = referenceArtifacts.sorted { $0.id.description < $1.id.description }
        self.referenceValue = referenceValue
        self.comparisonRule = comparisonRule
    }

    public func canonicalData() throws -> Data {
        guard schemaVersion == Self.currentSchemaVersion,
              ToolQualificationArtifactValidation.isVerifiable(metricDefinitionArtifact),
              ToolQualificationArtifactValidation.isVerifiable(requirementArtifact),
              referenceArtifacts.allSatisfy(ToolQualificationArtifactValidation.isVerifiable),
              ToolQualificationArtifactValidation.hasDistinctIdentities(referenceArtifacts),
              referenceArtifacts == referenceArtifacts.sorted(by: { $0.id.description < $1.id.description }),
              referenceValue.map(\.isFinite) ?? true,
              comparisonRule.absoluteTolerance(reference: referenceValue ?? 0) != nil,
              purpose != .physicalModelValidation || !referenceArtifacts.isEmpty else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput("invalid retained metric criterion")
        }
        return try ToolQualificationCanonicalJSON.encode(self)
    }

    public static func decodeCanonical(from data: Data) throws -> Self {
        let value = try ToolQualificationCanonicalJSON.decode(Self.self, from: data)
        guard try value.canonicalData() == data else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput("metric criterion is not canonical")
        }
        return value
    }
}
