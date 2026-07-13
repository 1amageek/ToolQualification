import Foundation

public protocol ToolProcessQualificationEvidenceBuilding: Sendable {
    func build(
        _ request: ToolProcessQualificationEvidenceBuildRequest,
        at date: Date
    ) throws -> ToolProcessQualificationEvidence
}
