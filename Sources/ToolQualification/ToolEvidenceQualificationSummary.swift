import Foundation

public struct ToolEvidenceQualificationSummary: Sendable, Hashable, Codable {
    public var qualified: Bool
    public var policyID: String?
    public var observedMetrics: [String: Double]
    public var observedCounts: [String: Int]
    public var failureCodes: [String]
    public var scope: ToolQualificationScope?
    public var qualificationID: String?
    public var independenceVerified: Bool

    public init(
        qualified: Bool,
        policyID: String? = nil,
        observedMetrics: [String: Double] = [:],
        observedCounts: [String: Int] = [:],
        failureCodes: [String] = [],
        scope: ToolQualificationScope? = nil,
        qualificationID: String? = nil,
        independenceVerified: Bool = false
    ) {
        self.qualified = qualified
        self.policyID = policyID
        self.observedMetrics = observedMetrics
        self.observedCounts = observedCounts
        self.failureCodes = failureCodes
        self.scope = scope
        self.qualificationID = qualificationID
        self.independenceVerified = independenceVerified
    }

    private enum CodingKeys: String, CodingKey {
        case qualified
        case policyID
        case observedMetrics
        case observedCounts
        case failureCodes
        case scope
        case qualificationID
        case independenceVerified
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            qualified: try container.decode(Bool.self, forKey: .qualified),
            policyID: try container.decodeIfPresent(String.self, forKey: .policyID),
            observedMetrics: try container.decodeIfPresent([String: Double].self, forKey: .observedMetrics) ?? [:],
            observedCounts: try container.decodeIfPresent([String: Int].self, forKey: .observedCounts) ?? [:],
            failureCodes: try container.decodeIfPresent([String].self, forKey: .failureCodes) ?? [],
            scope: try container.decodeIfPresent(ToolQualificationScope.self, forKey: .scope),
            qualificationID: try container.decodeIfPresent(String.self, forKey: .qualificationID),
            independenceVerified: try container.decodeIfPresent(Bool.self, forKey: .independenceVerified) ?? false
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(qualified, forKey: .qualified)
        try container.encodeIfPresent(policyID, forKey: .policyID)
        try container.encode(observedMetrics, forKey: .observedMetrics)
        try container.encode(observedCounts, forKey: .observedCounts)
        try container.encode(failureCodes, forKey: .failureCodes)
        try container.encodeIfPresent(scope, forKey: .scope)
        try container.encodeIfPresent(qualificationID, forKey: .qualificationID)
        try container.encode(independenceVerified, forKey: .independenceVerified)
    }
}
