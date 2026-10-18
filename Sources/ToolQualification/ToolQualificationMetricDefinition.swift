import CircuiteFoundation
import Foundation

/// Domain-owned meaning and extraction contract, independent of observations.
public struct ToolQualificationMetricDefinition: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1
    public let schemaVersion: Int
    public let metricID: String
    public let unitID: String
    public let extractionID: String
    public let domainArtifact: ArtifactReference

    public init(metricID: String, unitID: String, extractionID: String,
                domainArtifact: ArtifactReference, schemaVersion: Int = Self.currentSchemaVersion) {
        self.schemaVersion = schemaVersion
        self.metricID = metricID
        self.unitID = unitID
        self.extractionID = extractionID
        self.domainArtifact = domainArtifact
    }

    public func canonicalData() throws -> Data {
        guard schemaVersion == Self.currentSchemaVersion,
              [metricID, unitID, extractionID].allSatisfy(ToolQualificationArtifactValidation.isToken),
              ToolQualificationArtifactValidation.isVerifiable(domainArtifact) else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput("invalid retained metric definition")
        }
        return try ToolQualificationCanonicalJSON.encode(self)
    }

    public static func decodeCanonical(from data: Data) throws -> Self {
        let value = try ToolQualificationCanonicalJSON.decode(Self.self, from: data)
        _ = try value.canonicalData()
        return value
    }
}
