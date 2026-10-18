import Foundation
import CircuiteFoundation

public struct ToolTrustProfile: Sendable, Hashable, Codable {
    public var level: ToolQualificationLevel
    public var evidence: [ToolEvidence]
    public var processQualification: ToolProcessQualificationEvidence?
    public var assessmentPolicyArtifact: ArtifactReference?
    public var knownLimitations: [String]

    public init(
        level: ToolQualificationLevel,
        evidence: [ToolEvidence] = [],
        processQualification: ToolProcessQualificationEvidence? = nil,
        knownLimitations: [String] = [],
        assessmentPolicyArtifact: ArtifactReference? = nil
    ) {
        self.level = level
        self.evidence = evidence
        self.processQualification = processQualification
        self.knownLimitations = knownLimitations
        self.assessmentPolicyArtifact = assessmentPolicyArtifact
    }

    public var isStructurallyValid: Bool {
        evidence.allSatisfy(\.isStructurallyValid)
            && Set(evidence.map(\.evidenceID)).count == evidence.count
            && knownLimitations.allSatisfy {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            && Set(knownLimitations).count == knownLimitations.count
            && (processQualification?.isStructurallyValid ?? true)
    }
}
