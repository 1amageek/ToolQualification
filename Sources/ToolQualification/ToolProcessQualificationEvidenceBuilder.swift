import Foundation
import CircuiteFoundation

public struct ToolProcessQualificationEvidenceBuilder: ToolProcessQualificationEvidenceBuilding {
    public init() {}

    public func build(
        _ request: ToolProcessQualificationEvidenceBuildRequest,
        reading artifacts: any ToolQualificationArtifactReading,
        at date: Date
    ) async throws -> ToolProcessQualificationEvidence {
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
        guard request.scope.isCompleteForProduction,
              !request.requirePDKScope || request.scope.isCompleteForPDK else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput(
                "production qualification requires tool version, binary, process, PDK, deck, and independent oracle scope"
            )
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

        try await validateIdentityArtifacts(
            request.identityArtifacts,
            scope: request.scope,
            reading: artifacts
        )
        _ = try await validateArtifacts(
            request.evidenceArtifacts,
            reading: artifacts
        )
        let inputArtifacts = try await validateBoundArtifacts(
            request.inputArtifacts,
            label: "inputArtifacts",
            reading: artifacts
        )
        let outputArtifacts = try await validateBoundArtifacts(
            request.outputArtifacts,
            label: "outputArtifacts",
            reading: artifacts
        )
        let corpusEvidence = try await corpusEvidence(
            request: request,
            inputArtifacts: inputArtifacts,
            outputArtifacts: outputArtifacts,
            reading: artifacts,
            evaluatedAt: date
        )
        let oracleEvidence = try await oracleEvidence(
            request: request,
            inputArtifacts: inputArtifacts,
            outputArtifacts: outputArtifacts,
            reading: artifacts,
            evaluatedAt: date
        )
        let healthEvidence = try await healthEvidence(
            request: request,
            inputArtifacts: inputArtifacts,
            outputArtifacts: outputArtifacts,
            reading: artifacts,
            evaluatedAt: date
        )
        let evidenceIDs = (corpusEvidence + oracleEvidence + healthEvidence)
            .map(\.evidenceID)
        guard Set(evidenceIDs).count == evidenceIDs.count else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput(
                "qualification result IDs must be unique"
            )
        }

        return ToolProcessQualificationEvidence(
            qualificationID: request.qualificationID,
            toolID: request.toolID,
            scope: request.scope,
            identityArtifacts: request.identityArtifacts,
            status: .qualified,
            corpusEvidence: corpusEvidence,
            oracleEvidence: oracleEvidence,
            healthEvidence: healthEvidence,
            inputArtifacts: inputArtifacts,
            outputArtifacts: outputArtifacts,
            qualifiedModelIDs: request.qualifiedModelIDs,
            blockers: [],
            qualifiedAt: request.qualifiedAt,
            expiresAt: request.expiresAt
        )
    }

    private func corpusEvidence(
        request: ToolProcessQualificationEvidenceBuildRequest,
        inputArtifacts: [ArtifactReference],
        outputArtifacts: [ArtifactReference],
        reading artifacts: any ToolQualificationArtifactReading,
        evaluatedAt: Date
    ) async throws -> [ToolEvidence] {
        guard !request.corpusResultArtifacts.isEmpty else {
            throw ToolProcessQualificationEvidenceBuildError.missingEvidence(.corpus)
        }
        var evidenceItems: [ToolEvidence] = []
        for artifact in request.corpusResultArtifacts {
            let result = try ToolCorpusQualificationResult.decodeCanonical(
                from: await artifacts.verifiedData(for: artifact)
            )
            guard result.isPassing,
                  result.qualificationID == request.qualificationID,
                  result.toolID == request.toolID,
                  result.scope == request.scope,
                  issuerMatches(result.issuer, artifact: artifact),
                  result.checkedAt >= request.qualifiedAt,
                  result.checkedAt <= evaluatedAt,
                  Set(result.inputArtifacts).isSubset(of: Set(inputArtifacts)),
                  Set(result.outputArtifacts).isSubset(of: Set(outputArtifacts)) else {
                throw ToolProcessQualificationEvidenceBuildError.evidenceNotQualified(result.resultID)
            }
            evidenceItems.append(evidence(
                id: result.resultID,
                kind: .corpus,
                artifact: artifact,
                checkedAt: result.checkedAt
            ))
        }
        return evidenceItems
    }

    private func oracleEvidence(
        request: ToolProcessQualificationEvidenceBuildRequest,
        inputArtifacts: [ArtifactReference],
        outputArtifacts: [ArtifactReference],
        reading artifacts: any ToolQualificationArtifactReading,
        evaluatedAt: Date
    ) async throws -> [ToolEvidence] {
        guard !request.oracleResultArtifacts.isEmpty else {
            throw ToolProcessQualificationEvidenceBuildError.missingEvidence(.oracle)
        }
        var evidenceItems: [ToolEvidence] = []
        for artifact in request.oracleResultArtifacts {
            let result = try ToolOracleQualificationResult.decodeCanonical(
                from: await artifacts.verifiedData(for: artifact)
            )
            guard result.isPassing,
                  result.qualificationID == request.qualificationID,
                  result.primaryToolID == request.toolID,
                  result.scope == request.scope,
                  issuerMatches(result.issuer, artifact: artifact),
                  result.checkedAt >= request.qualifiedAt,
                  result.checkedAt <= evaluatedAt,
                  Set(result.inputArtifacts).isSubset(of: Set(inputArtifacts)),
                  Set(result.primaryOutputArtifacts).isSubset(of: Set(outputArtifacts)),
                  Set(result.oracleOutputArtifacts).isSubset(of: Set(outputArtifacts)) else {
                throw ToolProcessQualificationEvidenceBuildError.evidenceNotQualified(result.resultID)
            }
            evidenceItems.append(evidence(
                id: result.resultID,
                kind: .oracle,
                artifact: artifact,
                checkedAt: result.checkedAt
            ))
        }
        return evidenceItems
    }

    private func healthEvidence(
        request: ToolProcessQualificationEvidenceBuildRequest,
        inputArtifacts: [ArtifactReference],
        outputArtifacts: [ArtifactReference],
        reading artifacts: any ToolQualificationArtifactReading,
        evaluatedAt: Date
    ) async throws -> [ToolEvidence] {
        guard !request.healthResultArtifacts.isEmpty else {
            throw ToolProcessQualificationEvidenceBuildError.missingEvidence(.healthCheck)
        }
        var evidenceItems: [ToolEvidence] = []
        for artifact in request.healthResultArtifacts {
            let result = try ToolHealthQualificationResult.decodeCanonical(
                from: await artifacts.verifiedData(for: artifact)
            )
            guard result.isPassing,
                  result.qualificationID == request.qualificationID,
                  result.toolID == request.toolID,
                  result.scope == request.scope,
                  issuerMatches(result.issuer, artifact: artifact),
                  result.checkedAt >= request.qualifiedAt,
                  result.checkedAt <= evaluatedAt,
                  Set(result.inputArtifacts).isSubset(of: Set(inputArtifacts)),
                  Set(result.outputArtifacts).isSubset(of: Set(outputArtifacts)) else {
                throw ToolProcessQualificationEvidenceBuildError.evidenceNotQualified(result.resultID)
            }
            evidenceItems.append(evidence(
                id: result.resultID,
                kind: .healthCheck,
                artifact: artifact,
                checkedAt: result.checkedAt
            ))
        }
        return evidenceItems
    }

    private func evidence(
        id: String,
        kind: ToolEvidenceKind,
        artifact: ArtifactReference,
        checkedAt: Date
    ) -> ToolEvidence {
        ToolEvidence(
            evidenceID: id,
            kind: kind,
            artifact: artifact,
            checkedAt: checkedAt
        )
    }

    private func issuerMatches(
        _ issuer: ProducerIdentity,
        artifact: ArtifactReference
    ) -> Bool {
        issuer.kind == .engine && artifact.producer == issuer
    }

    private func validateArtifacts(
        _ artifacts: [ArtifactReference],
        reading reader: any ToolQualificationArtifactReading
    ) async throws -> [String: ArtifactReference] {
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
                  !artifact.locator.location.value.isEmpty,
                  artifact.digest.algorithm == .sha256,
                  artifact.byteCount > 0 else {
                throw ToolProcessQualificationEvidenceBuildError.invalidArtifact(
                    artifactID(artifact)
                )
            }
            _ = try await reader.verifiedData(for: artifact)
            artifactsByKey[key] = artifact
        }
        return artifactsByKey
    }

    private func validateBoundArtifacts(
        _ artifacts: [ArtifactReference],
        label: String,
        reading reader: any ToolQualificationArtifactReading
    ) async throws -> [ArtifactReference] {
        guard !artifacts.isEmpty else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput(
                "\(label) must retain at least one immutable artifact reference"
            )
        }
        var seen = Set<String>()
        for artifact in artifacts {
            let key = artifactKey(artifact)
            guard seen.insert(key).inserted else {
                throw ToolProcessQualificationEvidenceBuildError.duplicateArtifact(
                    artifactID(artifact)
                )
            }
            guard artifact.locator.location.storage == .workspaceRelative,
                  !artifact.locator.location.value.isEmpty,
                  artifact.digest.algorithm == .sha256,
                  artifact.byteCount > 0 else {
                throw ToolProcessQualificationEvidenceBuildError.invalidArtifact(
                    artifactID(artifact)
                )
            }
            _ = try await reader.verifiedData(for: artifact)
        }
        return artifacts
    }

    private func validateIdentityArtifacts(
        _ artifacts: ToolProcessQualificationArtifacts,
        scope: ToolQualificationScope,
        reading reader: any ToolQualificationArtifactReading
    ) async throws {
        guard Set(artifacts.all).count == artifacts.all.count else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput(
                "tool, process, PDK, deck, and oracle identity artifacts must be distinct"
            )
        }
        for artifact in artifacts.all {
            _ = try await reader.verifiedData(for: artifact)
        }

        guard artifacts.toolExecutable.digest.hexadecimalValue.caseInsensitiveCompare(scope.binaryDigest) == .orderedSame,
              artifacts.processProfile.digest.hexadecimalValue.caseInsensitiveCompare(scope.processProfileDigest) == .orderedSame,
              artifacts.pdk.digest.hexadecimalValue.caseInsensitiveCompare(scope.pdkDigest ?? "") == .orderedSame,
              artifacts.ruleDeck.digest.hexadecimalValue.caseInsensitiveCompare(scope.deckDigest) == .orderedSame,
              artifacts.oracleExecutable.digest.hexadecimalValue.caseInsensitiveCompare(scope.oracle?.binaryDigest ?? "") == .orderedSame else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput(
                "identity artifact digests must match the exact tool, process, PDK, deck, and oracle scope"
            )
        }
        guard let toolProducer = artifacts.toolExecutable.producer,
              toolProducer.kind == .tool,
              toolProducer.identifier == scope.implementationID,
              toolProducer.version == scope.toolVersion,
              let oracleProducer = artifacts.oracleExecutable.producer,
              oracleProducer.kind == .tool,
              oracleProducer.identifier == scope.oracle?.implementationID,
              oracleProducer.version == scope.oracle?.version else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput(
                "tool and oracle executable artifacts must bind their exact producer identifiers and versions"
            )
        }
    }

    private func artifactKey(_ artifact: ArtifactReference) -> String {
        "\(artifact.id.rawValue)|\(artifact.locator.location.value)"
    }

    private func artifactID(_ artifact: ArtifactReference) -> String {
        artifact.id.rawValue
    }
}
