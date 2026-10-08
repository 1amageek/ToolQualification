import Foundation
import CircuiteFoundation

public struct ToolProcessQualificationEvidenceBuilder: ToolProcessQualificationEvidenceBuilding {
    private struct VerifiedCase {
        let outcome: ToolQualificationCaseOutcome
        let execution: ToolQualificationCaseExecution
        let receipts: [ToolQualificationModelExecutionReceipt]
    }

    private struct VerifiedOracleCase {
        let comparison: ToolOracleCaseComparison
        let primary: VerifiedCase
        let oracle: VerifiedCase
    }

    private struct ModelMeaning: Hashable {
        let phaseID: String
        let modelID: String
        let source: ArtifactReference
        let selectedModelIdentifier: String
        let consumedInstances: [String: [String: Double]]
        let inputs: [ArtifactReference]
        let version: String?
        let parameters: [String: Double]

        init(_ receipt: ToolQualificationModelExecutionReceipt) {
            phaseID = receipt.phaseID
            modelID = receipt.modelID
            source = receipt.sourceArtifact
            selectedModelIdentifier = receipt.selectedModelIdentifier
            consumedInstances = receipt.consumedInstances
            inputs = receipt.inputArtifacts
            version = receipt.modelVersion
            parameters = receipt.resolvedParameters
        }
    }

    private struct ConsumptionScope: Hashable {
        let phaseID: String
        let modelID: String
    }
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
              request.toolID == request.scope.implementationID,
              !request.requirePDKScope || request.scope.isCompleteForPDK else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput(
                "production qualification requires tool version, binary, process, PDK, deck, and independent oracle scope"
            )
        }
        guard request.qualifiedAt.timeIntervalSinceReferenceDate.isFinite,
              request.expiresAt.timeIntervalSinceReferenceDate.isFinite,
              date.timeIntervalSinceReferenceDate.isFinite else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput(
                "qualification timestamps must be finite"
            )
        }
        guard request.qualifiedAt < request.expiresAt else {
            throw ToolProcessQualificationEvidenceBuildError.invalidValidityWindow
        }
        guard request.qualifiedAt <= date, date < request.expiresAt else {
            throw ToolProcessQualificationEvidenceBuildError.notValidAt
        }
        guard request.qualifiedModelIDs.allSatisfy(ToolQualificationArtifactValidation.isToken) else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput(
                "qualifiedModelIDs must contain valid model identity tokens"
            )
        }
        guard request.requiredOperatingCornerIDs.allSatisfy(ToolQualificationArtifactValidation.isToken) else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput(
                "requiredOperatingCornerIDs must not contain empty values"
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
        guard Set(inputArtifacts.map(artifactIdentityKey))
            .isDisjoint(with: Set(outputArtifacts.map(artifactIdentityKey))),
              Set(inputArtifacts.map { $0.id.description })
                .isDisjoint(with: Set(outputArtifacts.map { $0.id.description })) else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput(
                "inputArtifacts and outputArtifacts must identify distinct retained artifacts"
            )
        }
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
        let qualifiedModelIDs = try caseBoundModels(
            corpus: corpusEvidence.cases, oracle: oracleEvidence.cases
        )
        let missingModels = Set(request.qualifiedModelIDs).subtracting(qualifiedModelIDs)
        guard missingModels.isEmpty else {
            throw ToolProcessQualificationEvidenceBuildError.unexecutedModels(missingModels.sorted())
        }
        let evidenceIDs = (corpusEvidence.evidence + oracleEvidence.evidence + healthEvidence)
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
            corpusEvidence: corpusEvidence.evidence,
            oracleEvidence: oracleEvidence.evidence,
            healthEvidence: healthEvidence,
            inputArtifacts: inputArtifacts,
            outputArtifacts: outputArtifacts,
            qualifiedModelIDs: qualifiedModelIDs.sorted(),
            qualifiedOperatingCornerIDs: request.requiredOperatingCornerIDs,
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
    ) async throws -> (evidence: [ToolEvidence], cases: [String: VerifiedCase]) {
        guard !request.corpusResultArtifacts.isEmpty else {
            throw ToolProcessQualificationEvidenceBuildError.missingEvidence(.corpus)
        }
        var evidenceItems: [ToolEvidence] = []
        var cases: [String: VerifiedCase] = [:]
        for artifact in request.corpusResultArtifacts {
            let data = try await artifacts.verifiedData(for: artifact)
            let result: ToolCorpusQualificationResult
            do {
                result = try ToolCorpusQualificationResult.decodeCanonical(from: data)
            } catch {
                throw ToolProcessQualificationEvidenceBuildError.invalidInput(
                    "invalid retained corpus result: \(error.localizedDescription)"
                )
            }
            guard result.isPassing,
                  result.coverage.covers(
                    operatingCornerIDs: request.requiredOperatingCornerIDs
                  ),
                  result.qualificationID == request.qualificationID,
                  result.toolID == request.toolID,
                  result.scope == request.scope,
                  result.issuer.kind == .engine,
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
            for outcome in result.cases {
                if let existing = cases[outcome.caseID], existing.outcome != outcome {
                    throw ToolProcessQualificationEvidenceBuildError.conflictingCase(outcome.caseID)
                }
                guard result.outputArtifacts.contains(outcome.originalExecutionArtifact) else {
                    throw ToolProcessQualificationEvidenceBuildError.caseBindingMismatch(
                        caseID: outcome.caseID, reason: "corpus does not retain the original case output"
                    )
                }
                let verified = try await verifiedExecution(
                    outcome, executable: request.identityArtifacts.toolExecutable,
                    implementationID: request.scope.implementationID, version: request.scope.toolVersion,
                    request: request, reading: artifacts
                )
                try requireInventory(verified, inputs: result.inputArtifacts, outputs: result.outputArtifacts)
                cases[outcome.caseID] = verified
            }
        }
        return (evidenceItems, cases)
    }

    private func oracleEvidence(
        request: ToolProcessQualificationEvidenceBuildRequest,
        inputArtifacts: [ArtifactReference],
        outputArtifacts: [ArtifactReference],
        reading artifacts: any ToolQualificationArtifactReading,
        evaluatedAt: Date
    ) async throws -> (evidence: [ToolEvidence], cases: [String: VerifiedOracleCase]) {
        guard !request.oracleResultArtifacts.isEmpty else {
            throw ToolProcessQualificationEvidenceBuildError.missingEvidence(.oracle)
        }
        var evidenceItems: [ToolEvidence] = []
        var cases: [String: VerifiedOracleCase] = [:]
        for artifact in request.oracleResultArtifacts {
            let data = try await artifacts.verifiedData(for: artifact)
            let result: ToolOracleQualificationResult
            do {
                result = try ToolOracleQualificationResult.decodeCanonical(from: data)
            } catch {
                throw ToolProcessQualificationEvidenceBuildError.invalidInput(
                    "invalid retained oracle result: \(error.localizedDescription)"
                )
            }
            guard result.isStructurallyValid,
                  result.coverage.covers(
                    operatingCornerIDs: request.requiredOperatingCornerIDs
                  ),
                  Set(result.primaryOutputArtifacts.map(artifactIdentityKey))
                    .isDisjoint(with: Set(result.oracleOutputArtifacts.map(artifactIdentityKey))),
                  result.qualificationID == request.qualificationID,
                  result.primaryToolID == request.toolID,
                  result.scope == request.scope,
                  result.issuer.kind == .engine,
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
            for comparison in result.cases {
                if let existing = cases[comparison.caseID], existing.comparison != comparison {
                    throw ToolProcessQualificationEvidenceBuildError.conflictingCase(comparison.caseID)
                }
                guard result.primaryOutputArtifacts.contains(comparison.primary.originalExecutionArtifact),
                      result.oracleOutputArtifacts.contains(comparison.oracle.originalExecutionArtifact) else {
                    throw ToolProcessQualificationEvidenceBuildError.caseBindingMismatch(
                        caseID: comparison.caseID, reason: "oracle does not retain both original case outputs"
                    )
                }
                guard let oracleScope = request.scope.oracle else {
                    throw ToolProcessQualificationEvidenceBuildError.invalidInput("independent oracle scope is absent")
                }
                let primary = try await verifiedExecution(
                    comparison.primary, executable: request.identityArtifacts.toolExecutable,
                    implementationID: request.scope.implementationID, version: request.scope.toolVersion,
                    request: request, reading: artifacts
                )
                let oracle = try await verifiedExecution(
                    comparison.oracle, executable: request.identityArtifacts.oracleExecutable,
                    implementationID: oracleScope.implementationID, version: oracleScope.version,
                    request: request, reading: artifacts
                )
                try requireInventory(primary, inputs: result.inputArtifacts, outputs: result.primaryOutputArtifacts)
                try requireInventory(oracle, inputs: result.inputArtifacts, outputs: result.oracleOutputArtifacts)
                cases[comparison.caseID] = VerifiedOracleCase(comparison: comparison, primary: primary, oracle: oracle)
            }
        }
        return (evidenceItems, cases)
    }

    private func caseBoundModels(
        corpus: [String: VerifiedCase],
        oracle: [String: VerifiedOracleCase]
    ) throws -> Set<String> {
        let missingCases = Set(corpus.keys).symmetricDifference(Set(oracle.keys))
        if let caseID = missingCases.sorted().first {
            throw ToolProcessQualificationEvidenceBuildError.missingCase(caseID)
        }
        var coveredModels = Set<String>()
        for caseID in corpus.keys.sorted() {
            guard let primaryExecution = corpus[caseID], let oracleCase = oracle[caseID],
                  primaryExecution.outcome == oracleCase.comparison.primary else {
                throw ToolProcessQualificationEvidenceBuildError.caseBindingMismatch(
                    caseID: caseID, reason: "oracle primary does not exactly match the corpus primary"
                )
            }
            guard oracleCase.comparison.primaryPassed,
                  oracleCase.comparison.oraclePassed,
                  oracleCase.comparison.agreed,
                  oracleCase.comparison.failureCodes.isEmpty else {
                throw ToolProcessQualificationEvidenceBuildError.evidenceNotQualified(caseID)
            }
            let oracleExecution = oracleCase.oracle
            guard primaryExecution.outcome.originalExecutionArtifact != oracleExecution.outcome.originalExecutionArtifact,
                  primaryExecution.execution.executionID != oracleExecution.execution.executionID,
                  primaryExecution.execution.inputArtifacts == oracleExecution.execution.inputArtifacts,
                  primaryExecution.execution.phaseIDs == oracleExecution.execution.phaseIDs,
                  primaryExecution.execution.metricPhaseIDs == oracleExecution.execution.metricPhaseIDs,
                  Set(primaryExecution.execution.modelReceiptArtifacts)
                    .isDisjoint(with: Set(oracleExecution.execution.modelReceiptArtifacts)) else {
                throw ToolProcessQualificationEvidenceBuildError.caseBindingMismatch(
                    caseID: caseID, reason: "independent executions require distinct outputs and receipts with identical case inputs and phase bindings"
                )
            }
            guard Set(primaryExecution.receipts.map(ModelMeaning.init))
                == Set(oracleExecution.receipts.map(ModelMeaning.init)) else {
                throw ToolProcessQualificationEvidenceBuildError.caseBindingMismatch(
                    caseID: caseID, reason: "primary and oracle selected model source, version, phases, instances or resolved conditions differ"
                )
            }
            let observedPhases = Set(primaryExecution.execution.metricPhaseIDs.values.joined())
            for receipt in primaryExecution.receipts where observedPhases.contains(receipt.phaseID) {
                coveredModels.insert(receipt.modelID)
            }
        }
        return coveredModels
    }

    private func requireInventory(
        _ verified: VerifiedCase,
        inputs: [ArtifactReference],
        outputs: [ArtifactReference]
    ) throws {
        guard Set(verified.execution.inputArtifacts).isSubset(of: Set(inputs)),
              Set(verified.execution.modelReceiptArtifacts).isSubset(of: Set(outputs)) else {
            throw ToolProcessQualificationEvidenceBuildError.caseBindingMismatch(
                caseID: verified.outcome.caseID,
                reason: "case result inventory does not retain its original inputs and model receipts"
            )
        }
    }

    private func verifiedExecution(
        _ outcome: ToolQualificationCaseOutcome,
        executable: ArtifactReference,
        implementationID: String,
        version: String,
        request: ToolProcessQualificationEvidenceBuildRequest,
        reading artifacts: any ToolQualificationArtifactReading
    ) async throws -> VerifiedCase {
        let originalData = try await artifacts.verifiedData(for: outcome.originalExecutionArtifact)
        let execution: ToolQualificationCaseExecution
        do {
            execution = try ToolQualificationCaseExecution.decodeCanonical(from: originalData)
        } catch {
            throw ToolProcessQualificationEvidenceBuildError.caseBindingMismatch(
                caseID: outcome.caseID, reason: "invalid original execution: \(error.localizedDescription)"
            )
        }
        guard execution.caseID == outcome.caseID,
              execution.executableArtifact == executable,
              ToolQualificationArtifactValidation.isExecutionProducerKind(execution.producer.kind),
              execution.producer.identifier == implementationID,
              execution.producer.version == version,
              execution.observedMetrics == Dictionary(uniqueKeysWithValues: outcome.comparisons.map { ($0.metricID, $0.observed) }),
              Set(execution.inputArtifacts).isSubset(of: Set(request.inputArtifacts)),
              Set(execution.modelReceiptArtifacts).isSubset(of: Set(request.outputArtifacts)),
              !execution.modelReceiptArtifacts.contains(outcome.originalExecutionArtifact) else {
            throw ToolProcessQualificationEvidenceBuildError.caseBindingMismatch(
                caseID: outcome.caseID, reason: "original observations, executable, producer or retained inventory does not match"
            )
        }
        _ = try await artifacts.verifiedData(for: execution.executableArtifact)
        for input in execution.inputArtifacts { _ = try await artifacts.verifiedData(for: input) }
        var receipts: [ToolQualificationModelExecutionReceipt] = []
        var consumedByScope: [ConsumptionScope: Set<String>] = [:]
        for reference in execution.modelReceiptArtifacts {
            let receiptData = try await artifacts.verifiedData(for: reference)
            let receipt: ToolQualificationModelExecutionReceipt
            do {
                receipt = try ToolQualificationModelExecutionReceipt.decodeCanonical(from: receiptData)
            } catch {
                throw ToolProcessQualificationEvidenceBuildError.caseBindingMismatch(
                    caseID: outcome.caseID, reason: "invalid consumed-model receipt: \(error.localizedDescription)"
                )
            }
            let consumptionScope = ConsumptionScope(phaseID: receipt.phaseID, modelID: receipt.modelID)
            guard receipt.caseID == execution.caseID,
                  receipt.executionID == execution.executionID,
                  receipt.producer == execution.producer,
                  receipt.inputArtifacts == execution.inputArtifacts,
                  execution.phaseIDs.contains(receipt.phaseID),
                  Set(receipt.consumedInstances.keys).isDisjoint(with: consumedByScope[consumptionScope] ?? []) else {
                throw ToolProcessQualificationEvidenceBuildError.caseBindingMismatch(
                    caseID: outcome.caseID, reason: "receipt has a different execution/input/phase binding or duplicates a consumed instance within one phase"
                )
            }
            _ = try await artifacts.verifiedData(for: receipt.sourceArtifact)
            for input in receipt.inputArtifacts { _ = try await artifacts.verifiedData(for: input) }
            consumedByScope[consumptionScope, default: []].formUnion(receipt.consumedInstances.keys)
            receipts.append(receipt)
        }
        return VerifiedCase(outcome: outcome, execution: execution, receipts: receipts)
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
                  result.issuer.kind == .engine,
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
        var artifactIDs = Set<String>()
        for artifact in artifacts {
            let key = artifactIdentityKey(artifact)
            guard artifactsByKey[key] == nil,
                  artifactIDs.insert(artifact.id.description).inserted else {
                throw ToolProcessQualificationEvidenceBuildError.duplicateArtifact(
                    artifactID(artifact)
                )
            }
            guard ToolQualificationArtifactValidation.isVerifiable(artifact) else {
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
        var seenIDs = Set<String>()
        for artifact in artifacts {
            let key = artifactIdentityKey(artifact)
            guard seen.insert(key).inserted,
                  seenIDs.insert(artifact.id.description).inserted else {
                throw ToolProcessQualificationEvidenceBuildError.duplicateArtifact(
                    artifactID(artifact)
                )
            }
            guard ToolQualificationArtifactValidation.isVerifiable(artifact) else {
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
        guard Set(artifacts.all.map(artifactIdentityKey)).count == artifacts.all.count,
              Set(artifacts.all.map { $0.id.description }).count == artifacts.all.count else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput(
                "tool, process, PDK, deck, and oracle identity artifacts must be distinct"
            )
        }
        for artifact in artifacts.all {
            guard isVerifiableArtifact(artifact) else {
                throw ToolProcessQualificationEvidenceBuildError.invalidArtifact(
                    artifactID(artifact)
                )
            }
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
    }

    private func artifactIdentityKey(_ artifact: ArtifactReference) -> String {
        ToolQualificationArtifactValidation.identityKey(artifact)
    }

    private func artifactID(_ artifact: ArtifactReference) -> String {
        artifact.id.description
    }

    private func isVerifiableArtifact(_ artifact: ArtifactReference) -> Bool {
        ToolQualificationArtifactValidation.isVerifiable(artifact)
    }
}
