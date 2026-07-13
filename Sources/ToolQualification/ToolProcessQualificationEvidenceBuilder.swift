import Foundation
import CircuiteFoundation

public struct ToolProcessQualificationEvidenceBuilder: ToolProcessQualificationEvidenceBuilding {
    public init() {}

    public func build(
        _ request: ToolProcessQualificationEvidenceBuildRequest,
        at date: Date
    ) throws -> ToolProcessQualificationEvidence {
        guard request.schemaVersion == ToolProcessQualificationEvidenceBuildRequest.currentSchemaVersion else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput(
                "unsupported schema version \(request.schemaVersion)"
            )
        }
        guard !request.qualificationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !request.toolID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput(
                "qualificationID and toolID are required"
            )
        }
        guard request.scope.isComplete,
              !request.requirePDKScope || request.scope.isCompleteForPDK else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput(
                request.requirePDKScope ? "complete PDK scope is required" : "complete qualification scope is required"
            )
        }
        guard request.independenceVerified else {
            throw ToolProcessQualificationEvidenceBuildError.independenceRequired
        }
        guard request.qualifiedAt < request.expiresAt else {
            throw ToolProcessQualificationEvidenceBuildError.invalidValidityWindow
        }
        guard request.qualifiedAt <= date, date < request.expiresAt else {
            throw ToolProcessQualificationEvidenceBuildError.notValidAt
        }
        guard request.qualifiedModelIDs.allSatisfy({
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput(
                "qualifiedModelIDs must not contain empty values"
            )
        }

        let evidenceArtifactsByKey = try validateArtifacts(request.evidenceArtifacts)
        var evidenceIDs = Set<String>()
        var referencedArtifactKeys = Set<String>()
        let corpusIDs = try validateGroup(
            request.corpusEvidence,
            expectedKind: .corpus,
            scope: request.scope,
            evidenceArtifactsByKey: evidenceArtifactsByKey,
            evidenceIDs: &evidenceIDs,
            referencedArtifactKeys: &referencedArtifactKeys
        )
        let oracleIDs = try validateGroup(
            request.oracleEvidence,
            expectedKind: .oracle,
            scope: request.scope,
            evidenceArtifactsByKey: evidenceArtifactsByKey,
            evidenceIDs: &evidenceIDs,
            referencedArtifactKeys: &referencedArtifactKeys
        )
        let healthIDs = try validateGroup(
            request.healthEvidence,
            expectedKind: .healthCheck,
            scope: request.scope,
            evidenceArtifactsByKey: evidenceArtifactsByKey,
            evidenceIDs: &evidenceIDs,
            referencedArtifactKeys: &referencedArtifactKeys
        )
        let approvalIDs = try validateGroup(
            request.approvalEvidence,
            expectedKind: .productionApproval,
            scope: request.scope,
            evidenceArtifactsByKey: evidenceArtifactsByKey,
            evidenceIDs: &evidenceIDs,
            referencedArtifactKeys: &referencedArtifactKeys
        )
        guard referencedArtifactKeys == Set(evidenceArtifactsByKey.keys) else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput(
                "every evidence artifact must be referenced by at least one evidence item"
            )
        }

        return ToolProcessQualificationEvidence(
            qualificationID: request.qualificationID,
            toolID: request.toolID,
            scope: request.scope,
            status: .qualified,
            corpusEvidenceIDs: corpusIDs,
            oracleEvidenceIDs: oracleIDs,
            healthEvidenceIDs: healthIDs,
            approvalEvidenceIDs: approvalIDs,
            evidenceArtifactIDs: request.evidenceArtifacts.map(artifactID),
            qualifiedModelIDs: request.qualifiedModelIDs,
            independenceVerified: true,
            blockers: [],
            qualifiedAt: request.qualifiedAt,
            expiresAt: request.expiresAt
        )
    }

    private func validateGroup(
        _ evidence: [ToolEvidence],
        expectedKind: ToolEvidenceKind,
        scope: ToolQualificationScope,
        evidenceArtifactsByKey: [String: ArtifactReference],
        evidenceIDs: inout Set<String>,
        referencedArtifactKeys: inout Set<String>
    ) throws -> [String] {
        guard !evidence.isEmpty else {
            throw ToolProcessQualificationEvidenceBuildError.missingEvidence(expectedKind)
        }
        var ids: [String] = []
        for item in evidence {
            let evidenceID = item.evidenceID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !evidenceID.isEmpty else {
                throw ToolProcessQualificationEvidenceBuildError.invalidInput(
                    "evidence IDs must not be empty"
                )
            }
            guard evidenceIDs.insert(evidenceID).inserted else {
                throw ToolProcessQualificationEvidenceBuildError.duplicateEvidenceID(evidenceID)
            }
            guard item.kind == expectedKind else {
                throw ToolProcessQualificationEvidenceBuildError.evidenceKindMismatch(
                    evidenceID: evidenceID,
                    expected: expectedKind,
                    actual: item.kind
                )
            }
            guard item.hasPassingQualificationSupport(
                requiredScope: scope,
                requireIndependentQualificationEvidence: true
            ) else {
                throw ToolProcessQualificationEvidenceBuildError.evidenceNotQualified(evidenceID)
            }
            guard let artifact = item.artifact else {
                throw ToolProcessQualificationEvidenceBuildError.evidenceArtifactMissing(evidenceID)
            }
            let key = artifactKey(artifact)
            guard let declaredArtifact = evidenceArtifactsByKey[key], declaredArtifact == artifact else {
                throw ToolProcessQualificationEvidenceBuildError.invalidInput(
                    "artifact for evidence \(evidenceID) is not exactly bound to evidenceArtifacts"
                )
            }
            referencedArtifactKeys.insert(key)
            ids.append(evidenceID)
        }
        return ids.sorted()
    }

    private func validateArtifacts(
        _ artifacts: [ArtifactReference]
    ) throws -> [String: ArtifactReference] {
        guard !artifacts.isEmpty else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput(
                "evidenceArtifacts must not be empty"
            )
        }
        var artifactsByKey: [String: ArtifactReference] = [:]
        for artifact in artifacts {
            let key = artifactKey(artifact)
            guard artifactsByKey[key] == nil else {
                throw ToolProcessQualificationEvidenceBuildError.duplicateArtifact(
                    artifactID(artifact)
                )
            }
            guard artifact.locator.location.storage == .workspaceRelative,
                  !artifact.locator.location.value.isEmpty else {
                throw ToolProcessQualificationEvidenceBuildError.invalidArtifact(
                    artifactID(artifact)
                )
            }
            artifactsByKey[key] = artifact
        }
        return artifactsByKey
    }

    private func artifactKey(_ artifact: ArtifactReference) -> String {
        "\(artifact.id.rawValue)|\(artifact.locator.location.value)"
    }

    private func artifactID(_ artifact: ArtifactReference) -> String {
        artifact.id.rawValue
    }
}
