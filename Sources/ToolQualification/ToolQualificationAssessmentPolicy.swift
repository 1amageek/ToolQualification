import Foundation

/// An immutable policy input pinned before case execution.
public struct ToolQualificationAssessmentPolicy: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1
    public let schemaVersion: Int
    public let policyID: String
    public let requirements: [ToolQualificationMetricRequirement]

    public init(policyID: String, requirements: [ToolQualificationMetricRequirement],
                schemaVersion: Int = Self.currentSchemaVersion) {
        self.schemaVersion = schemaVersion
        self.policyID = policyID
        self.requirements = requirements.sorted { ($0.caseID, $0.metricID) < ($1.caseID, $1.metricID) }
    }

    public func canonicalData() throws -> Data {
        let identities = requirements.map { $0.caseID + "\u{0}" + $0.metricID }
        guard schemaVersion == Self.currentSchemaVersion,
              ToolQualificationArtifactValidation.isToken(policyID), !requirements.isEmpty,
              requirements.allSatisfy(\.isStructurallyValid),
              Set(identities).count == identities.count else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput("invalid retained assessment policy")
        }
        let normalized = Self(policyID: policyID, requirements: requirements, schemaVersion: schemaVersion)
        return try ToolQualificationCanonicalJSON.encode(normalized)
    }

    public static func decodeCanonical(from data: Data) throws -> Self {
        let value = try ToolQualificationCanonicalJSON.decode(Self.self, from: data)
        guard try value.canonicalData() == data else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput("assessment policy is not canonical")
        }
        return value
    }
}
