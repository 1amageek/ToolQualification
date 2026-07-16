import Foundation

public enum ToolQualificationRecordError: Error, LocalizedError, Sendable, Hashable {
    case invalidStructure
    case issuanceRejected(toolID: String, operationID: String)
    case toolIdentityMismatch(expected: String, actual: String)
    case issuerMismatch
    case issuanceDecisionMismatch(operationID: String)

    public var errorDescription: String? {
        switch self {
        case .invalidStructure:
            "Tool qualification record is not structurally valid."
        case .issuanceRejected(let toolID, let operationID):
            "Tool qualification record issuance rejected tool \(toolID) for operation \(operationID)."
        case .toolIdentityMismatch(let expected, let actual):
            "Tool qualification record belongs to \(actual), expected \(expected)."
        case .issuerMismatch:
            "Tool qualification record issuer does not match its artifact producer."
        case .issuanceDecisionMismatch(let operationID):
            "Tool qualification record decision cannot be reproduced for operation \(operationID)."
        }
    }
}
