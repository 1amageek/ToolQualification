import Foundation

public enum ToolProcessQualificationEvidenceBuildError: Error, LocalizedError, Sendable, Hashable {
    case invalidInput(String)
    case missingEvidence(ToolEvidenceKind)
    case evidenceKindMismatch(evidenceID: String, expected: ToolEvidenceKind, actual: ToolEvidenceKind)
    case duplicateEvidenceID(String)
    case evidenceNotQualified(String)
    case evidenceArtifactMissing(String)
    case invalidArtifact(String)
    case duplicateArtifact(String)
    case artifactAvailabilityMissing(String)
    case artifactAccessFailed(String)
    case artifactCloseFailed(String)
    case artifactIntegrityFailed(String)
    case invalidValidityWindow
    case notValidAt
    case caseBindingMismatch(caseID: String, reason: String)
    case conflictingCase(String)
    case missingCase(String)
    case unexecutedModels([String])

    public var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return "process qualification evidence build input is invalid: \(message)"
        case .missingEvidence(let kind):
            return "process qualification requires at least one \(kind.rawValue) evidence item"
        case .evidenceKindMismatch(let evidenceID, let expected, let actual):
            return "evidence \(evidenceID) has kind \(actual.rawValue), expected \(expected.rawValue)"
        case .duplicateEvidenceID(let evidenceID):
            return "evidence ID \(evidenceID) is duplicated"
        case .evidenceNotQualified(let evidenceID):
            return "retained evidence \(evidenceID) does not derive a passing qualification from its raw result"
        case .evidenceArtifactMissing(let evidenceID):
            return "evidence \(evidenceID) has no artifact reference"
        case .invalidArtifact(let message):
            return "evidence artifact is invalid: \(message)"
        case .duplicateArtifact(let artifactID):
            return "evidence artifact \(artifactID) is duplicated"
        case .artifactAvailabilityMissing(let artifactID):
            return "artifact availability is missing for \(artifactID)"
        case .artifactAccessFailed(let message):
            return "process qualification artifact access failed: \(message)"
        case .artifactCloseFailed(let message):
            return "process qualification artifact close failed: \(message)"
        case .artifactIntegrityFailed(let message):
            return "process qualification artifact integrity failed: \(message)"
        case .invalidValidityWindow:
            return "qualifiedAt must precede expiresAt"
        case .notValidAt:
            return "the requested evaluation time is outside the qualification validity window"
        case .caseBindingMismatch(let caseID, let reason):
            return "case \(caseID) execution binding failed: \(reason)"
        case .conflictingCase(let caseID):
            return "conflicting qualification case \(caseID)"
        case .missingCase(let caseID):
            return "qualification case \(caseID) has no matched corpus and oracle execution"
        case .unexecutedModels(let modelIDs):
            return "requested models have no matched executed receipts: \(modelIDs.joined(separator: ", "))"
        }
    }
}
