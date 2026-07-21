import CircuiteFoundation
import Foundation
import Testing

@testable import ToolQualification

@Suite("Tool trust evaluator")
struct ToolTrustEvaluatorTests {
    @Test func structurallyInvalidDescriptorIsRejectedAtDirectEvaluatorEntry() async throws {
        let fixture = try QualificationFixture()
        var descriptor = fixture.descriptor(level: .unknown, evidence: [])
        descriptor.capabilities = []

        let decision = await ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: fixture.requirement(minimumLevel: .unknown),
            health: nil
        )

        #expect(decision.status == .rejected)
        #expect(decision.diagnostics.contains { $0.code == "TOOL_DESCRIPTOR_STRUCTURALLY_INVALID" })
    }

    @Test func nonfiniteEvaluationTimestampIsRejected() async throws {
        let fixture = try QualificationFixture()
        let descriptor = fixture.descriptor(level: .unknown, evidence: [])

        let decision = await ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: fixture.requirement(minimumLevel: .unknown),
            health: nil,
            evaluatedAt: Date(timeIntervalSinceReferenceDate: .infinity)
        )

        #expect(decision.status == .rejected)
        #expect(decision.diagnostics.contains { $0.code == "INVALID_EVALUATION_TIMESTAMP" })
    }

    @Test("serialized trust requirements require the independence field")
    func trustRequirementRejectsMissingIndependenceField() throws {
        let data = Data("""
        {
          "kind":"drc",
          "operationID":"run-drc",
          "minimumLevel":"unknown",
          "requiredInputFormats":[],
          "requiredOutputFormats":[],
          "requiredEvidenceKinds":[],
          "requiredQualifiedEvidenceKinds":[],
          "requirePassingHealthCheck":false
        }
        """.utf8)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(ToolTrustRequirement.self, from: data)
        }
    }

    @Test func corpusCheckedToolRequiresVerifiedPassingArtifact() async throws {
        let fixture = try QualificationFixture()
        let evidence = try await fixture.corpusEvidence(passing: true)
        let descriptor = fixture.descriptor(level: .corpusChecked, evidence: [evidence])

        let decision = await ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: fixture.requirement(minimumLevel: .corpusChecked),
            health: ToolHealthCheckResult(toolID: descriptor.toolID, status: .passed),
            artifactReader: fixture.reader
        )

        #expect(decision.status == .eligible)
        #expect(decision.diagnostics.isEmpty)
    }

    @Test func callerEvidenceWithoutArtifactCannotClaimQualification() async throws {
        let fixture = try QualificationFixture()
        let descriptor = fixture.descriptor(
            level: .corpusChecked,
            evidence: [ToolEvidence(evidenceID: "corpus", kind: .corpus)]
        )

        let decision = await ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: fixture.requirement(minimumLevel: .corpusChecked),
            health: ToolHealthCheckResult(toolID: descriptor.toolID, status: .passed),
            artifactReader: fixture.reader
        )

        #expect(decision.status == .rejected)
        #expect(decision.diagnostics.contains { $0.code == "QUALIFICATION_EVIDENCE_ARTIFACT_MISSING" })
        #expect(decision.diagnostics.contains { $0.code == "UNQUALIFIED_REQUIRED_EVIDENCE" })
    }

    @Test func failingRawMetricCannotClaimQualification() async throws {
        let fixture = try QualificationFixture()
        let evidence = try await fixture.corpusEvidence(passing: false)
        let descriptor = fixture.descriptor(level: .corpusChecked, evidence: [evidence])

        let decision = await ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: fixture.requirement(minimumLevel: .corpusChecked),
            health: ToolHealthCheckResult(toolID: descriptor.toolID, status: .passed),
            artifactReader: fixture.reader
        )

        #expect(decision.status == .rejected)
        #expect(decision.diagnostics.contains { $0.code == "QUALIFICATION_EVIDENCE_CASE_MISMATCH" })
    }

    @Test func noncanonicalRawResultIsRejected() async throws {
        let fixture = try QualificationFixture()
        let evidence = try await fixture.corpusEvidence(passing: true, canonical: false)
        let descriptor = fixture.descriptor(level: .corpusChecked, evidence: [evidence])

        let decision = await ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: fixture.requirement(minimumLevel: .corpusChecked),
            health: ToolHealthCheckResult(toolID: descriptor.toolID, status: .passed),
            artifactReader: fixture.reader
        )

        #expect(decision.status == .rejected)
        #expect(decision.diagnostics.contains { $0.code == "QUALIFICATION_EVIDENCE_NONCANONICAL" })
    }

    @Test func artifactIntegrityFailureIsTyped() async throws {
        let fixture = try QualificationFixture()
        let evidence = try await fixture.corpusEvidence(passing: true)
        let descriptor = fixture.descriptor(level: .corpusChecked, evidence: [evidence])

        let decision = await ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: fixture.requirement(minimumLevel: .corpusChecked),
            health: ToolHealthCheckResult(toolID: descriptor.toolID, status: .passed),
            artifactReader: FailingQualificationArtifactReader()
        )

        #expect(decision.status == .rejected)
        #expect(decision.diagnostics.contains { $0.code == "QUALIFICATION_EVIDENCE_INTEGRITY_FAILED" })
    }

    @Test func scopeMismatchIsRejected() async throws {
        let fixture = try QualificationFixture()
        let evidence = try await fixture.corpusEvidence(passing: true)
        let descriptor = fixture.descriptor(level: .corpusChecked, evidence: [evidence])
        var otherScope = fixture.scope
        otherScope.algorithmVersion = "different-algorithm"

        let decision = await ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: fixture.requirement(
                minimumLevel: .corpusChecked,
                qualificationScope: otherScope
            ),
            health: ToolHealthCheckResult(toolID: descriptor.toolID, status: .passed),
            artifactReader: fixture.reader
        )

        #expect(decision.status == .rejected)
        #expect(decision.diagnostics.contains { $0.code == "QUALIFICATION_EVIDENCE_SCOPE_MISMATCH" })
    }

    @Test func freshnessRejectsMissingAndFutureTimestamps() async throws {
        let fixture = try QualificationFixture()
        let evaluatedAt = Date(timeIntervalSince1970: 1_000)
        let descriptor = fixture.descriptor(
            level: .corpusChecked,
            evidence: [ToolEvidence(
                evidenceID: "future",
                kind: .corpus,
                artifact: fixture.outputArtifact,
                checkedAt: Date(timeIntervalSince1970: 2_000)
            )]
        )

        let decision = await ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: fixture.requirement(
                minimumLevel: .corpusChecked,
                maximumEvidenceAgeSeconds: 60
            ),
            health: ToolHealthCheckResult(toolID: descriptor.toolID, status: .passed),
            artifactReader: fixture.reader,
            evaluatedAt: evaluatedAt
        )

        #expect(decision.status == .rejected)
        #expect(decision.diagnostics.contains {
            $0.code == "STALE_REQUIRED_EVIDENCE" && $0.message.contains("future")
        })
    }

    @Test func futureEvidenceIsRejectedWithoutAnAgeLimit() async throws {
        let fixture = try QualificationFixture()
        let descriptor = fixture.descriptor(
            level: .corpusChecked,
            evidence: [ToolEvidence(
                evidenceID: "future",
                kind: .corpus,
                artifact: fixture.outputArtifact,
                checkedAt: fixture.checkedAt.addingTimeInterval(1)
            )]
        )

        let decision = await ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: fixture.requirement(minimumLevel: .corpusChecked),
            health: ToolHealthCheckResult(toolID: descriptor.toolID, status: .passed),
            artifactReader: fixture.reader,
            evaluatedAt: fixture.checkedAt
        )

        #expect(decision.status == .rejected)
        #expect(decision.diagnostics.contains {
            $0.code == "STALE_REQUIRED_EVIDENCE" && $0.message.contains("future")
        })
    }

    @Test func evidenceIdentifierMustMatchCanonicalResultIdentifier() async throws {
        let fixture = try QualificationFixture()
        let evidence = try await fixture.corpusEvidence(passing: true)
        let mismatched = ToolEvidence(
            evidenceID: "different-result",
            kind: evidence.kind,
            artifact: evidence.artifact,
            checkedAt: evidence.checkedAt
        )
        let descriptor = fixture.descriptor(level: .corpusChecked, evidence: [mismatched])

        let decision = await ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: fixture.requirement(minimumLevel: .corpusChecked),
            health: ToolHealthCheckResult(toolID: descriptor.toolID, status: .passed),
            artifactReader: fixture.reader,
            evaluatedAt: fixture.checkedAt
        )

        #expect(decision.status == .rejected)
        #expect(decision.diagnostics.contains { $0.code == "QUALIFICATION_EVIDENCE_IDENTITY_MISMATCH" })
    }

    @Test func retainedResultInputsAndOutputsAreReverified() async throws {
        let fixture = try QualificationFixture()
        let evidence = try await fixture.corpusEvidence(passing: true)
        await fixture.reader.remove(fixture.outputArtifact)
        let descriptor = fixture.descriptor(level: .corpusChecked, evidence: [evidence])

        let decision = await ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: fixture.requirement(minimumLevel: .corpusChecked),
            health: ToolHealthCheckResult(toolID: descriptor.toolID, status: .passed),
            artifactReader: fixture.reader,
            evaluatedAt: fixture.checkedAt
        )

        #expect(decision.status == .rejected)
        #expect(decision.diagnostics.contains {
            $0.code == "QUALIFICATION_BOUND_ARTIFACT_INTEGRITY_FAILED"
        })
    }

    @Test func productionLevelRequiresProcessEvidenceAndArtifactReader() async throws {
        let fixture = try QualificationFixture()
        let descriptor = fixture.descriptor(level: .productionEligible, evidence: [])

        let decision = await ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: fixture.requirement(minimumLevel: .productionEligible),
            health: ToolHealthCheckResult(toolID: descriptor.toolID, status: .passed)
        )

        #expect(decision.status == .rejected)
        #expect(decision.diagnostics.contains { $0.code == "PRODUCTION_QUALIFICATION_REQUIRED" })
    }

    @Test func mismatchedHealthResultIsRejectedAndItsEvidenceIgnored() async throws {
        let fixture = try QualificationFixture()
        let descriptor = fixture.descriptor(level: .corpusChecked, evidence: [])
        let externalEvidence = try await fixture.corpusEvidence(passing: true)

        let decision = await ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: fixture.requirement(minimumLevel: .corpusChecked),
            health: ToolHealthCheckResult(
                toolID: "different-tool",
                status: .passed,
                evidence: [externalEvidence]
            ),
            artifactReader: fixture.reader
        )

        #expect(decision.status == .rejected)
        #expect(decision.diagnostics.contains { $0.code == "HEALTH_CHECK_TOOL_ID_MISMATCH" })
        #expect(decision.diagnostics.contains { $0.code == "MISSING_REQUIRED_EVIDENCE" })
    }

    @Test func passingHealthCannotContainAnErrorDiagnostic() async throws {
        let fixture = try QualificationFixture()
        let descriptor = fixture.descriptor(level: .unknown, evidence: [])
        let health = ToolHealthCheckResult(
            toolID: descriptor.toolID,
            status: .passed,
            diagnostics: [ToolDiagnostic(
                severity: .error,
                code: "PROBE_FAILED",
                message: "Version probe failed."
            )]
        )

        let decision = await ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: fixture.requirement(minimumLevel: .unknown),
            health: health
        )

        #expect(decision.status == .rejected)
        #expect(decision.diagnostics.contains { $0.code == "HEALTH_CHECK_STRUCTURALLY_INVALID" })
    }

    @Test func failedHealthCheckIsRejected() async throws {
        let fixture = try QualificationFixture()
        let evidence = try await fixture.corpusEvidence(passing: true)
        let descriptor = fixture.descriptor(level: .corpusChecked, evidence: [evidence])

        let decision = await ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: fixture.requirement(minimumLevel: .corpusChecked),
            health: ToolHealthCheckResult(toolID: descriptor.toolID, status: .failed),
            artifactReader: fixture.reader
        )

        #expect(decision.status == .rejected)
        #expect(decision.diagnostics.contains { $0.code == "HEALTH_CHECK_FAILED" })
    }

    @Test func missingCapabilityAndFormatsAreRejected() async throws {
        let fixture = try QualificationFixture()
        let evidence = try await fixture.corpusEvidence(passing: true)
        let descriptor = fixture.descriptor(
            level: .corpusChecked,
            evidence: [evidence],
            capabilities: [ToolCapability(
                operationID: "other-operation",
                inputFormats: [.json],
                outputFormats: [.json]
            )]
        )

        let decision = await ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: fixture.requirement(minimumLevel: .corpusChecked),
            health: ToolHealthCheckResult(toolID: descriptor.toolID, status: .passed),
            artifactReader: fixture.reader
        )

        #expect(decision.status == .rejected)
        #expect(decision.diagnostics.contains { $0.code == "MISSING_CAPABILITY" })
    }

    @Test func toolKindMismatchIsRejected() async throws {
        let fixture = try QualificationFixture()
        let descriptor = fixture.descriptor(level: .unknown, evidence: [])
        let requirement = ToolTrustRequirement(
            kind: .lvs,
            operationID: "run-drc",
            minimumLevel: .unknown,
            requirePassingHealthCheck: false
        )

        let decision = await ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: requirement,
            health: nil
        )

        #expect(decision.status == .rejected)
        #expect(decision.diagnostics.contains { $0.code == "TOOL_KIND_MISMATCH" })
    }

    @Test func insufficientTrustLevelIsRejected() async throws {
        let fixture = try QualificationFixture()
        let descriptor = fixture.descriptor(level: .unknown, evidence: [])

        let decision = await ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: fixture.requirement(minimumLevel: .corpusChecked),
            health: ToolHealthCheckResult(toolID: descriptor.toolID, status: .passed)
        )

        #expect(decision.status == .rejected)
        #expect(decision.diagnostics.contains { $0.code == "INSUFFICIENT_TRUST_LEVEL" })
    }

    @Test func missingInputFormatIsRejected() async throws {
        let fixture = try QualificationFixture()
        let descriptor = fixture.descriptor(
            level: .unknown,
            evidence: [],
            capabilities: [ToolCapability(operationID: "run-drc", inputFormats: [.gdsii], outputFormats: [.json])]
        )

        let decision = await ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: fixture.requirement(minimumLevel: .unknown),
            health: ToolHealthCheckResult(toolID: descriptor.toolID, status: .passed)
        )

        #expect(decision.diagnostics.contains { $0.code == "MISSING_INPUT_FORMAT" })
    }

    @Test func missingOutputFormatIsRejected() async throws {
        let fixture = try QualificationFixture()
        let descriptor = fixture.descriptor(
            level: .unknown,
            evidence: [],
            capabilities: [ToolCapability(operationID: "run-drc", inputFormats: [.oasis], outputFormats: [.text])]
        )

        let decision = await ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: fixture.requirement(minimumLevel: .unknown),
            health: ToolHealthCheckResult(toolID: descriptor.toolID, status: .passed)
        )

        #expect(decision.diagnostics.contains { $0.code == "MISSING_OUTPUT_FORMAT" })
    }

    @Test func missingHealthCheckIsRejected() async throws {
        let fixture = try QualificationFixture()
        let descriptor = fixture.descriptor(level: .unknown, evidence: [])

        let decision = await ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: fixture.requirement(minimumLevel: .unknown),
            health: nil
        )

        #expect(decision.diagnostics.contains { $0.code == "HEALTH_CHECK_REQUIRED" })
    }

    @Test func blockedHealthCheckIsRejected() async throws {
        let fixture = try QualificationFixture()
        let descriptor = fixture.descriptor(level: .unknown, evidence: [])

        let decision = await ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: fixture.requirement(minimumLevel: .unknown),
            health: ToolHealthCheckResult(toolID: descriptor.toolID, status: .blocked)
        )

        #expect(decision.diagnostics.contains { $0.code == "HEALTH_CHECK_BLOCKED" })
    }

    @Test func healthCheckCanBeOptional() async throws {
        let fixture = try QualificationFixture()
        let descriptor = fixture.descriptor(level: .unknown, evidence: [])
        let requirement = ToolTrustRequirement(
            kind: .drc,
            operationID: "run-drc",
            minimumLevel: .unknown,
            requiredInputFormats: [.oasis],
            requiredOutputFormats: [.json],
            requirePassingHealthCheck: false
        )

        let decision = await ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: requirement,
            health: nil
        )

        #expect(decision.status == .eligible)
    }

    @Test func invalidZeroFreshnessRequirementIsRejected() async throws {
        let fixture = try QualificationFixture()
        let evidence = try await fixture.corpusEvidence(passing: true)
        let descriptor = fixture.descriptor(level: .corpusChecked, evidence: [evidence])

        let decision = await ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: fixture.requirement(minimumLevel: .corpusChecked, maximumEvidenceAgeSeconds: 0),
            health: ToolHealthCheckResult(toolID: descriptor.toolID, status: .passed),
            artifactReader: fixture.reader,
            evaluatedAt: fixture.checkedAt
        )

        #expect(decision.diagnostics.contains { $0.code == "INVALID_EVIDENCE_FRESHNESS_REQUIREMENT" })
    }

    @Test func staleEvidenceIsRejected() async throws {
        let fixture = try QualificationFixture()
        let evidence = try await fixture.corpusEvidence(passing: true)
        let descriptor = fixture.descriptor(level: .corpusChecked, evidence: [evidence])

        let decision = await ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: fixture.requirement(minimumLevel: .corpusChecked, maximumEvidenceAgeSeconds: 10),
            health: ToolHealthCheckResult(toolID: descriptor.toolID, status: .passed),
            artifactReader: fixture.reader,
            evaluatedAt: fixture.checkedAt.addingTimeInterval(11)
        )

        #expect(decision.diagnostics.contains { $0.code == "STALE_REQUIRED_EVIDENCE" })
    }

    @Test func rawEvidenceKindDoesNotRequireQualificationArtifact() async throws {
        let fixture = try QualificationFixture()
        let descriptor = fixture.descriptor(
            level: .unknown,
            evidence: [ToolEvidence(evidenceID: "health-log", kind: .healthCheck, checkedAt: fixture.checkedAt)]
        )
        let requirement = ToolTrustRequirement(
            kind: .drc,
            operationID: "run-drc",
            minimumLevel: .unknown,
            requiredInputFormats: [.oasis],
            requiredOutputFormats: [.json],
            requiredEvidenceKinds: [.healthCheck],
            requirePassingHealthCheck: false
        )

        let decision = await ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: requirement,
            health: nil,
            evaluatedAt: fixture.checkedAt
        )

        #expect(decision.status == .eligible)
    }

    @Test func qualifiedEvidenceRequiresArtifactReader() async throws {
        let fixture = try QualificationFixture()
        let evidence = try await fixture.corpusEvidence(passing: true)
        let descriptor = fixture.descriptor(level: .corpusChecked, evidence: [evidence])

        let decision = await ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: fixture.requirement(minimumLevel: .corpusChecked),
            health: ToolHealthCheckResult(toolID: descriptor.toolID, status: .passed)
        )

        #expect(decision.diagnostics.contains { $0.code == "UNQUALIFIED_REQUIRED_EVIDENCE" })
    }

    @Test func healthEvidenceForMatchingToolParticipatesInQualification() async throws {
        let fixture = try QualificationFixture()
        let evidence = try await fixture.corpusEvidence(passing: true)
        let descriptor = fixture.descriptor(level: .corpusChecked, evidence: [])

        let decision = await ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: fixture.requirement(minimumLevel: .corpusChecked),
            health: ToolHealthCheckResult(toolID: descriptor.toolID, status: .passed, evidence: [evidence]),
            artifactReader: fixture.reader,
            evaluatedAt: fixture.checkedAt
        )

        #expect(decision.status == .eligible)
    }

    @Test func requiredQualifiedEvidenceFailsClosedWhenTimestampIsMissing() async throws {
        let fixture = try QualificationFixture()
        let descriptor = fixture.descriptor(
            level: .unknown,
            evidence: [ToolEvidence(evidenceID: "corpus", kind: .corpus, artifact: fixture.outputArtifact)]
        )
        let requirement = ToolTrustRequirement(
            kind: .drc,
            operationID: "run-drc",
            minimumLevel: .unknown,
            requiredInputFormats: [.oasis],
            requiredOutputFormats: [.json],
            requiredQualifiedEvidenceKinds: [.corpus],
            maximumEvidenceAgeSeconds: 60,
            requirePassingHealthCheck: false
        )

        let decision = await ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: requirement,
            health: nil,
            artifactReader: fixture.reader,
            evaluatedAt: fixture.checkedAt
        )

        #expect(decision.diagnostics.contains { $0.code == "STALE_REQUIRED_EVIDENCE" })
        #expect(decision.diagnostics.contains { $0.code == "UNQUALIFIED_REQUIRED_EVIDENCE" })
    }
}

private struct QualificationFixture {
    let checkedAt = Date(timeIntervalSince1970: 900)
    let issuer: ProducerIdentity
    let inputArtifact: ArtifactReference
    let outputArtifact: ArtifactReference
    let scope: ToolQualificationScope
    let reader: InMemoryQualificationArtifactReader

    init() throws {
        issuer = try ProducerIdentity(kind: .engine, identifier: "qualification-runner", version: "1")
        inputArtifact = try Self.artifact(id: "input", producer: issuer)
        outputArtifact = try Self.artifact(id: "output", producer: issuer)
        scope = ToolQualificationScope(
            implementationID: "native-drc",
            toolVersion: "1.0.0",
            binaryDigest: String(repeating: "a", count: 64),
            algorithmVersion: "native-drc-v1",
            processProfileID: "fixture-process",
            processProfileDigest: String(repeating: "b", count: 64),
            deckDigest: String(repeating: "c", count: 64),
            pdkID: "fixture-pdk",
            pdkDigest: String(repeating: "d", count: 64),
            oracle: ToolOracleQualificationScope(
                implementationID: "independent-drc",
                version: "2.0.0",
                binaryDigest: String(repeating: "e", count: 64)
            )
        )
        reader = InMemoryQualificationArtifactReader()
    }

    func corpusEvidence(passing: Bool, canonical: Bool = true) async throws -> ToolEvidence {
        await reader.insert(Data([0]), for: inputArtifact)
        await reader.insert(Data([0]), for: outputArtifact)
        let result = ToolCorpusQualificationResult(
            resultID: "corpus-result",
            qualificationID: "qualification",
            toolID: "native-drc",
            scope: scope,
            issuer: issuer,
            inputArtifacts: [inputArtifact],
            outputArtifacts: [outputArtifact],
            cases: [ToolQualificationCaseOutcome(
                caseID: "case",
                coverageTags: ["minimum-spacing"],
                comparisons: [ToolQualificationMetricComparison(
                    metricID: "violation-count",
                    observed: passing ? 0 : 1,
                    expected: 0,
                    absoluteTolerance: 0
                )]
            )],
            checkedAt: checkedAt
        )
        var data = try result.canonicalData()
        if !canonical {
            data.append(0x20)
        }
        let artifact = try Self.artifact(
            id: passing ? "corpus-pass" : "corpus-fail",
            producer: issuer,
            byteCount: UInt64(data.count)
        )
        await reader.insert(data, for: artifact)
        return ToolEvidence(
            evidenceID: result.resultID,
            kind: .corpus,
            artifact: artifact,
            checkedAt: result.checkedAt
        )
    }

    func descriptor(
        level: ToolQualificationLevel,
        evidence: [ToolEvidence],
        capabilities: [ToolCapability] = [ToolCapability(
            operationID: "run-drc",
            inputFormats: [.oasis],
            outputFormats: [.json]
        )]
    ) -> ToolDescriptor {
        ToolDescriptor(
            toolID: "native-drc",
            displayName: "Native DRC",
            kind: .drc,
            version: "1.0.0",
            capabilities: capabilities,
            trustProfile: ToolTrustProfile(level: level, evidence: evidence),
            environment: ToolEnvironment(platform: "macOS", requiredAssets: [])
        )
    }

    func requirement(
        minimumLevel: ToolQualificationLevel,
        qualificationScope: ToolQualificationScope? = nil,
        maximumEvidenceAgeSeconds: TimeInterval? = nil
    ) -> ToolTrustRequirement {
        ToolTrustRequirement(
            kind: .drc,
            operationID: "run-drc",
            minimumLevel: minimumLevel,
            requiredInputFormats: [.oasis],
            requiredOutputFormats: [.json],
            maximumEvidenceAgeSeconds: maximumEvidenceAgeSeconds,
            qualificationScope: qualificationScope
        )
    }

    private static func artifact(
        id: String,
        producer: ProducerIdentity,
        byteCount: UInt64 = 1
    ) throws -> ArtifactReference {
        ArtifactReference(
            id: try ArtifactID(rawValue: id),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: "qualification/\(id).json"),
                role: .output,
                kind: .report,
                format: .json
            ),
            digest: try ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: String(repeating: "f", count: 64)
            ),
            byteCount: byteCount,
            producer: producer
        )
    }
}

private actor InMemoryQualificationArtifactReader: ToolQualificationArtifactReading {
    private var dataByReference: [ArtifactReference: Data] = [:]

    func insert(_ data: Data, for reference: ArtifactReference) {
        dataByReference[reference] = data
    }

    func remove(_ reference: ArtifactReference) {
        dataByReference.removeValue(forKey: reference)
    }

    func verifiedData(for reference: ArtifactReference) async throws -> Data {
        guard let data = dataByReference[reference] else {
            throw ToolProcessQualificationEvidenceBuildError.artifactIntegrityFailed(reference.id.rawValue)
        }
        return data
    }
}

private struct FailingQualificationArtifactReader: ToolQualificationArtifactReading {
    func verifiedData(for reference: ArtifactReference) async throws -> Data {
        throw ToolProcessQualificationEvidenceBuildError.artifactIntegrityFailed(reference.id.rawValue)
    }
}
