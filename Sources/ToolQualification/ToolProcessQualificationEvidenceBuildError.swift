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
    case artifactIntegrityFailed(String)
    case invalidValidityWindow
    case notValidAt

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
        case .artifactIntegrityFailed(let message):
            return "process qualification artifact integrity failed: \(message)"
        case .invalidValidityWindow:
            return "qualifiedAt must precede expiresAt"
        case .notValidAt:
            return "the requested evaluation time is outside the qualification validity window"
        }
    }
}
