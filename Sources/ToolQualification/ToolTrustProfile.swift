import Foundation

public struct ToolTrustProfile: Sendable, Hashable, Codable {
    public var level: ToolQualificationLevel
    public var evidence: [ToolEvidence]
    public var processQualification: ToolProcessQualificationEvidence?
    public var knownLimitations: [String]

    public init(
        level: ToolQualificationLevel,
        evidence: [ToolEvidence] = [],
        processQualification: ToolProcessQualificationEvidence? = nil,
        knownLimitations: [String] = []
    ) {
        self.level = level
        self.evidence = evidence
        self.processQualification = processQualification
        self.knownLimitations = knownLimitations
    }
}
