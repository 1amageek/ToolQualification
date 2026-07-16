import Foundation

public protocol ToolProcessQualificationEvidenceBuilding: Sendable {
    func build(
        _ request: ToolProcessQualificationEvidenceBuildRequest,
        reading artifacts: any ToolQualificationArtifactReading,
        at date: Date
    ) async throws -> ToolProcessQualificationEvidence
}
