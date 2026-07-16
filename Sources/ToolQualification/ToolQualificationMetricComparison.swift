import Foundation

public struct ToolQualificationMetricComparison: Sendable, Hashable, Codable {
    public let metricID: String
    public let observed: Double
    public let expected: Double
    public let absoluteTolerance: Double

    public init(
        metricID: String,
        observed: Double,
        expected: Double,
        absoluteTolerance: Double = 0
    ) {
        self.metricID = metricID
        self.observed = observed
        self.expected = expected
        self.absoluteTolerance = absoluteTolerance
    }

    public var isStructurallyValid: Bool {
        !metricID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && observed.isFinite
            && expected.isFinite
            && absoluteTolerance.isFinite
            && absoluteTolerance >= 0
    }

    public var passed: Bool {
        isStructurallyValid && abs(observed - expected) <= absoluteTolerance
    }
}
