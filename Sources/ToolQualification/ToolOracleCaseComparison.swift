import Foundation

public struct ToolOracleCaseComparison: Sendable, Hashable, Codable {
    public let caseID: String
    public let primary: ToolQualificationCaseOutcome
    public let oracle: ToolQualificationCaseOutcome
    public let agreementComparisons: [ToolQualificationMetricComparison]

    public init(
        caseID: String,
        primary: ToolQualificationCaseOutcome,
        oracle: ToolQualificationCaseOutcome,
        agreementComparisons: [ToolQualificationMetricComparison]
    ) {
        self.caseID = caseID
        self.primary = primary
        self.oracle = oracle
        self.agreementComparisons = agreementComparisons.sorted { $0.metricID < $1.metricID }
    }

    public var isStructurallyValid: Bool {
        !caseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && primary.caseID == caseID
            && oracle.caseID == caseID
            && primary.isStructurallyValid
            && oracle.isStructurallyValid
            && !agreementComparisons.isEmpty
            && agreementComparisons.map(\.metricID) == agreementComparisons.map(\.metricID).sorted()
            && Set(agreementComparisons.map(\.metricID)).count == agreementComparisons.count
            && agreementComparisons.allSatisfy(\.isStructurallyValid)
    }

    public var primaryPassed: Bool { primary.passed }
    public var oraclePassed: Bool { oracle.passed }
    public var agreed: Bool {
        isStructurallyValid && agreementComparisons.allSatisfy(\.passed)
    }
    public var failureCodes: [String] {
        primary.failureCodes.map { "primary:\($0)" }
            + oracle.failureCodes.map { "oracle:\($0)" }
            + agreementComparisons.filter { !$0.passed }.map { "oracle-disagreement:\($0.metricID)" }
    }
}
