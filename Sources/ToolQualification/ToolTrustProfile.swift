import Foundation

public struct ToolTrustProfile: Sendable, Hashable, Codable {
    public var level: ToolQualificationLevel
    public var evidence: [ToolEvidence]
    public var knownLimitations: [String]

    public init(
        level: ToolQualificationLevel,
        evidence: [ToolEvidence] = [],
        knownLimitations: [String] = []
    ) {
        self.level = level
        self.evidence = evidence
        self.knownLimitations = knownLimitations
    }
}
