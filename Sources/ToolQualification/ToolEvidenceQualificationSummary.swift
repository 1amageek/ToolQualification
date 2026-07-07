import Foundation

public struct ToolEvidenceQualificationSummary: Sendable, Hashable, Codable {
    public var qualified: Bool
    public var policyID: String?
    public var observedMetrics: [String: Double]
    public var observedCounts: [String: Int]
    public var failureCodes: [String]

    public init(
        qualified: Bool,
        policyID: String? = nil,
        observedMetrics: [String: Double] = [:],
        observedCounts: [String: Int] = [:],
        failureCodes: [String] = []
    ) {
        self.qualified = qualified
        self.policyID = policyID
        self.observedMetrics = observedMetrics
        self.observedCounts = observedCounts
        self.failureCodes = failureCodes
    }
}
