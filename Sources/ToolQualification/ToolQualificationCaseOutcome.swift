import Foundation
import CircuiteFoundation

public struct ToolQualificationCaseOutcome: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1
    public let schemaVersion: Int
    public let caseID: String
    public let originalExecutionArtifact: ArtifactReference
    public let coverageTags: [String]
    public let comparisons: [ToolQualificationMetricComparison]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, caseID, originalExecutionArtifact, coverageTags, comparisons
    }

    public init(
        caseID: String,
        originalExecutionArtifact: ArtifactReference,
        coverageTags: [String],
        comparisons: [ToolQualificationMetricComparison],
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.caseID = caseID
        self.originalExecutionArtifact = originalExecutionArtifact
        self.coverageTags = Array(Set(coverageTags)).sorted()
        self.comparisons = comparisons.sorted { $0.metricID < $1.metricID }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: container,
                debugDescription: "Expected case outcome schema version \(Self.currentSchemaVersion).")
        }
        self.init(caseID: try container.decode(String.self, forKey: .caseID),
            originalExecutionArtifact: try container.decode(ArtifactReference.self, forKey: .originalExecutionArtifact),
            coverageTags: try container.decode([String].self, forKey: .coverageTags),
            comparisons: try container.decode([ToolQualificationMetricComparison].self, forKey: .comparisons),
            schemaVersion: version)
    }

    public var isStructurallyValid: Bool {
        schemaVersion == Self.currentSchemaVersion
            && !caseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && ToolQualificationArtifactValidation.isVerifiable(originalExecutionArtifact)
            && !coverageTags.isEmpty
            && coverageTags == Array(Set(coverageTags)).sorted()
            && !comparisons.isEmpty
            && comparisons.map(\.metricID) == comparisons.map(\.metricID).sorted()
            && Set(comparisons.map(\.metricID)).count == comparisons.count
            && comparisons.allSatisfy(\.isStructurallyValid)
    }

    public var passed: Bool {
        isStructurallyValid && comparisons.allSatisfy(\.passed)
    }

    public var failureCodes: [String] {
        comparisons.filter { !$0.passed }.map { "metric-mismatch:\($0.metricID)" }
    }
}
