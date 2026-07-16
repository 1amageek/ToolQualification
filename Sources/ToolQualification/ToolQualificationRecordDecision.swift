import Foundation

public struct ToolQualificationRecordDecision: Sendable, Hashable, Codable {
    public let operationID: String
    public let decision: ToolTrustDecision

    public init(operationID: String, decision: ToolTrustDecision) {
        self.operationID = operationID
        self.decision = decision
    }
}
