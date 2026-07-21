import Foundation

public struct ToolOracleCaseComparison: Sendable, Hashable, Codable {
    public let caseID: String
    public let primary: ToolQualificationCaseOutcome
    public let oracle: ToolQualificationCaseOutcome
    public let agreementComparisons: [ToolOracleMetricComparison]

    public init(
        caseID: String,
        primary: ToolQualificationCaseOutcome,
        oracle: ToolQualificationCaseOutcome,
        agreementComparisons: [ToolOracleMetricComparison]
    ) {
        self.caseID = caseID
        self.primary = primary
        self.oracle = oracle
        self.agreementComparisons = agreementComparisons.sorted { $0.metricID < $1.metricID }
    }

    public var isStructurallyValid: Bool {
        guard primary.isStructurallyValid, oracle.isStructurallyValid else {
            return false
        }
        let primaryComparisons = Dictionary(
            uniqueKeysWithValues: primary.comparisons.map { ($0.metricID, $0) }
        )
        let oracleComparisons = Dictionary(
            uniqueKeysWithValues: oracle.comparisons.map { ($0.metricID, $0) }
        )
        return !caseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && primary.caseID == caseID
            && oracle.caseID == caseID
            && primary.coverageTags == oracle.coverageTags
            && !agreementComparisons.isEmpty
            && agreementComparisons.map(\.metricID) == agreementComparisons.map(\.metricID).sorted()
            && Set(agreementComparisons.map(\.metricID)).count == agreementComparisons.count
            && agreementComparisons.allSatisfy(\.isStructurallyValid)
            && Set(agreementComparisons.map(\.metricID)) == Set(primaryComparisons.keys)
            && Set(primaryComparisons.keys) == Set(oracleComparisons.keys)
            && agreementComparisons.allSatisfy { comparison in
                guard let primaryMetric = primaryComparisons[comparison.metricID],
                      let oracleMetric = oracleComparisons[comparison.metricID] else {
                    return false
                }
                return comparison.primaryObserved == primaryMetric.observed
                    && comparison.oracleObserved == oracleMetric.observed
            }
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
