import Foundation
import CircuiteFoundation

public struct ToolQualificationMetricComparison: Sendable, Hashable, Codable {
    public let metricID: String
    public let observed: Double
    public let expected: Double
    public let absoluteTolerance: Double
    public let criterionArtifact: ArtifactReference?

    public init(
        metricID: String,
        observed: Double,
        expected: Double,
        absoluteTolerance: Double = 0,
        criterionArtifact: ArtifactReference? = nil
    ) {
        self.metricID = metricID
        self.observed = observed
        self.expected = expected
        self.absoluteTolerance = absoluteTolerance
        self.criterionArtifact = criterionArtifact
    }

    public var isStructurallyValid: Bool {
        !metricID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && observed.isFinite
            && expected.isFinite
            && absoluteTolerance.isFinite
            && absoluteTolerance >= 0
            && (criterionArtifact.map(ToolQualificationArtifactValidation.isVerifiable) ?? true)
    }

    /// Numerical consistency; trust evaluation separately verifies policy and original artifacts.
    public var passed: Bool {
        isStructurallyValid && abs(observed - expected) <= absoluteTolerance
    }
}
