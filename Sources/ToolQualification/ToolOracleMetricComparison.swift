import Foundation

/// A metric comparison whose values are bound to the primary and oracle case outputs.
public struct ToolOracleMetricComparison: Sendable, Hashable, Codable {
    public let metricID: String
    public let primaryObserved: Double
    public let oracleObserved: Double
    public let absoluteTolerance: Double

    public init(
        metricID: String,
        primaryObserved: Double,
        oracleObserved: Double,
        absoluteTolerance: Double = 0
    ) {
        self.metricID = metricID
        self.primaryObserved = primaryObserved
        self.oracleObserved = oracleObserved
        self.absoluteTolerance = absoluteTolerance
    }

    public var isStructurallyValid: Bool {
        !metricID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && primaryObserved.isFinite
            && oracleObserved.isFinite
            && absoluteTolerance.isFinite
            && absoluteTolerance >= 0
    }

    public var passed: Bool {
        isStructurallyValid
            && abs(primaryObserved - oracleObserved) <= absoluteTolerance
    }
}
