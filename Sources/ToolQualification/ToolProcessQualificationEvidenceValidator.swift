import Foundation

public struct ToolProcessQualificationEvidenceValidator: ToolProcessQualificationEvidenceValidating, Sendable {
    private let builder: any ToolProcessQualificationEvidenceBuilding

    public init(
        builder: any ToolProcessQualificationEvidenceBuilding = ToolProcessQualificationEvidenceBuilder()
    ) {
        self.builder = builder
    }

    public func validate(
        _ evidence: ToolProcessQualificationEvidence,
        reading artifacts: any ToolQualificationArtifactReading,
        at date: Date
    ) async throws {
        guard evidence.status == .qualified,
              evidence.blockers.isEmpty,
              let qualifiedAt = evidence.qualifiedAt,
              let expiresAt = evidence.expiresAt else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput(
                "only complete qualified evidence can be validated"
            )
        }
        let request = ToolProcessQualificationEvidenceBuildRequest(
            qualificationID: evidence.qualificationID,
            toolID: evidence.toolID,
            scope: evidence.scope,
            identityArtifacts: evidence.identityArtifacts,
            corpusResultArtifacts: evidence.corpusEvidence.compactMap(\.artifact),
            oracleResultArtifacts: evidence.oracleEvidence.compactMap(\.artifact),
            healthResultArtifacts: evidence.healthEvidence.compactMap(\.artifact),
            inputArtifacts: evidence.inputArtifacts,
            outputArtifacts: evidence.outputArtifacts,
            qualifiedModelIDs: evidence.qualifiedModelIDs,
            requirePDKScope: true,
            qualifiedAt: qualifiedAt,
            expiresAt: expiresAt
        )
        let rebuilt = try await builder.build(request, reading: artifacts, at: date)
        guard rebuilt == evidence else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput(
                "persisted evidence does not match evidence derived from retained results"
            )
        }
    }
}
