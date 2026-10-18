import Foundation
import CircuiteFoundation

/// A metric comparison whose values are bound to the primary and oracle case outputs.
public struct ToolOracleMetricComparison: Sendable, Hashable, Codable {
    public let metricID: String
    public let primaryObserved: Double
    public let oracleObserved: Double
    public let absoluteTolerance: Double
    public let criterionArtifact: ArtifactReference?

    public init(
        metricID: String,
        primaryObserved: Double,
        oracleObserved: Double,
        absoluteTolerance: Double = 0,
        criterionArtifact: ArtifactReference? = nil
    ) {
        self.metricID = metricID
        self.primaryObserved = primaryObserved
        self.oracleObserved = oracleObserved
        self.absoluteTolerance = absoluteTolerance
        self.criterionArtifact = criterionArtifact
    }

    public var isStructurallyValid: Bool {
        !metricID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && primaryObserved.isFinite
            && oracleObserved.isFinite
            && absoluteTolerance.isFinite
            && absoluteTolerance >= 0
            && (criterionArtifact.map(ToolQualificationArtifactValidation.isVerifiable) ?? true)
    }

    /// Numerical consistency; trust evaluation separately verifies policy and original artifacts.
    public var passed: Bool {
        isStructurallyValid
            && abs(primaryObserved - oracleObserved) <= absoluteTolerance
    }
}
