import Foundation

public protocol ToolProcessQualificationEvidenceValidating: Sendable {
    func validate(
        _ evidence: ToolProcessQualificationEvidence,
        reading artifacts: any ToolQualificationArtifactReading,
        at date: Date
    ) async throws
}
