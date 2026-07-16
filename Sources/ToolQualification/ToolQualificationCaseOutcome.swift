import Foundation

public struct ToolQualificationCaseOutcome: Sendable, Hashable, Codable {
    public let caseID: String
    public let coverageTags: [String]
    public let comparisons: [ToolQualificationMetricComparison]

    public init(
        caseID: String,
        coverageTags: [String],
        comparisons: [ToolQualificationMetricComparison]
    ) {
        self.caseID = caseID
        self.coverageTags = Array(Set(coverageTags)).sorted()
        self.comparisons = comparisons.sorted { $0.metricID < $1.metricID }
    }

    public var isStructurallyValid: Bool {
        !caseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
