import Foundation
import Testing
import ToolQualification
import XcircuitePackage

@Suite("Tool trust evaluator")
struct ToolTrustEvaluatorTests {
    @Test func productionEligibleToolWithPassingHealthIsEligible() {
        let descriptor = makeDescriptor(level: .productionEligible)
        let requirement = makeRequirement(minimumLevel: .corpusChecked)
        let health = ToolHealthCheckResult(toolID: descriptor.toolID, status: .passed)

        let decision = ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: requirement,
            health: health
        )

        #expect(decision.status == .eligible)
        #expect(decision.diagnostics.isEmpty)
    }

    @Test func insufficientQualificationLevelIsRejected() {
        let descriptor = makeDescriptor(level: .unknown)
        let requirement = makeRequirement(minimumLevel: .corpusChecked)
        let health = ToolHealthCheckResult(toolID: descriptor.toolID, status: .passed)

        let decision = ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: requirement,
            health: health
        )

        #expect(decision.status == .rejected)
        #expect(decision.diagnostics.contains { $0.code == "INSUFFICIENT_TRUST_LEVEL" })
    }

    @Test func declaredProductionLevelWithoutSupportingEvidenceIsRejected() {
        let descriptor = makeDescriptor(level: .productionEligible, evidence: [])
        let requirement = makeRequirement(minimumLevel: .corpusChecked)
        let health = ToolHealthCheckResult(toolID: descriptor.toolID, status: .passed)

        let decision = ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: requirement,
            health: health
        )

        #expect(decision.status == .rejected)
        #expect(decision.diagnostics.contains { $0.code == "MISSING_REQUIRED_EVIDENCE" })
    }

    @Test func failedHealthCheckIsRejected() {
        let descriptor = makeDescriptor(level: .productionEligible)
        let requirement = makeRequirement(minimumLevel: .corpusChecked)
        let health = ToolHealthCheckResult(
            toolID: descriptor.toolID,
            status: .failed,
            diagnostics: [
                ToolDiagnostic(
                    severity: .error,
                    code: "SMOKE_FAILED",
                    message: "Smoke fixture failed."
                ),
            ]
        )

        let decision = ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: requirement,
            health: health
        )

        #expect(decision.status == .rejected)
        #expect(decision.diagnostics.contains { $0.code == "HEALTH_CHECK_FAILED" })
    }

    @Test func mismatchedHealthCheckToolIDIsRejectedAndEvidenceIgnored() {
        let descriptor = makeDescriptor(level: .productionEligible, evidence: [])
        let requirement = makeRequirement(
            minimumLevel: .corpusChecked,
            requiredQualifiedEvidenceKinds: [.corpus]
        )
        let health = ToolHealthCheckResult(
            toolID: "external-drc",
            status: .passed,
            evidence: [
                ToolEvidence(
                    evidenceID: "external-corpus",
                    kind: .corpus,
                    qualification: ToolEvidenceQualificationSummary(
                        qualified: true,
                        observedMetrics: ["passRate": 1],
                        observedCounts: ["caseCount": 12]
                    )
                ),
            ]
        )

        let decision = ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: requirement,
            health: health
        )

        #expect(decision.status == ToolTrustDecisionStatus.rejected)
        #expect(decision.diagnostics.contains { $0.code == "HEALTH_CHECK_TOOL_ID_MISMATCH" })
        #expect(decision.diagnostics.contains { $0.code == "HEALTH_CHECK_REQUIRED" })
        #expect(decision.diagnostics.contains { $0.code == "MISSING_REQUIRED_EVIDENCE" })
    }

    @Test func missingCapabilityIsRejected() {
        let descriptor = makeDescriptor(
            level: .productionEligible,
            capabilities: [
                ToolCapability(
                    operationID: "run-lvs",
                    inputFormats: [.spice],
                    outputFormats: [.json]
                ),
            ]
        )
        let requirement = makeRequirement(minimumLevel: .smokeChecked)
        let health = ToolHealthCheckResult(toolID: descriptor.toolID, status: .passed)

        let decision = ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: requirement,
            health: health
        )

        #expect(decision.status == .rejected)
        #expect(decision.diagnostics.contains { $0.code == "MISSING_CAPABILITY" })
    }

    @Test func missingFormatIsRejected() {
        let descriptor = makeDescriptor(
            level: .productionEligible,
            capabilities: [
                ToolCapability(
                    operationID: "run-drc",
                    inputFormats: [.json],
                    outputFormats: [.json]
                ),
            ]
        )
        let requirement = makeRequirement(minimumLevel: .smokeChecked)
        let health = ToolHealthCheckResult(toolID: descriptor.toolID, status: .passed)

        let decision = ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: requirement,
            health: health
        )

        #expect(decision.status == .rejected)
        #expect(decision.diagnostics.contains { $0.code == "MISSING_INPUT_FORMAT" })
    }

    @Test func requiredEvidenceKindIsRejectedWhenMissing() {
        let descriptor = makeDescriptor(level: .productionEligible, evidence: [])
        let requirement = makeRequirement(
            minimumLevel: .corpusChecked,
            requiredEvidenceKinds: [.corpus]
        )
        let health = ToolHealthCheckResult(
            toolID: descriptor.toolID,
            status: .passed,
            evidence: [
                ToolEvidence(evidenceID: "smoke-1", kind: .smoke),
            ]
        )

        let decision = ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: requirement,
            health: health
        )

        #expect(decision.status == .rejected)
        #expect(decision.diagnostics.contains { $0.code == "MISSING_REQUIRED_EVIDENCE" })
    }

    @Test func requiredEvidenceKindAllowsEligibleTool() {
        let descriptor = makeDescriptor(level: .productionEligible)
        let requirement = makeRequirement(
            minimumLevel: .corpusChecked,
            requiredEvidenceKinds: [.corpus, .healthCheck]
        )
        let health = ToolHealthCheckResult(
            toolID: descriptor.toolID,
            status: .passed,
            evidence: [
                ToolEvidence(evidenceID: "corpus-1", kind: .corpus),
                ToolEvidence(evidenceID: "health-1", kind: .healthCheck),
            ]
        )

        let decision = ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: requirement,
            health: health
        )

        #expect(decision.status == .eligible)
        #expect(!decision.diagnostics.contains { $0.severity == .error })
    }

    @Test func requiredQualifiedEvidenceKindIsRejectedWhenEvidenceIsMissing() {
        let descriptor = makeDescriptor(level: .productionEligible, evidence: [])
        let requirement = makeRequirement(
            minimumLevel: .corpusChecked,
            requiredQualifiedEvidenceKinds: [.corpus]
        )
        let health = ToolHealthCheckResult(toolID: descriptor.toolID, status: .passed)

        let decision = ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: requirement,
            health: health
        )

        #expect(decision.status == .rejected)
        #expect(decision.diagnostics.contains { $0.code == "MISSING_REQUIRED_EVIDENCE" })
        #expect(!decision.diagnostics.contains { $0.code == "UNQUALIFIED_REQUIRED_EVIDENCE" })
    }

    @Test func requiredQualifiedEvidenceKindIsRejectedWhenQualificationIsMissing() {
        let descriptor = makeDescriptor(level: .productionEligible, evidence: [])
        let requirement = makeRequirement(
            minimumLevel: .corpusChecked,
            requiredQualifiedEvidenceKinds: [.corpus]
        )
        let health = ToolHealthCheckResult(
            toolID: descriptor.toolID,
            status: .passed,
            evidence: [
                ToolEvidence(evidenceID: "corpus-1", kind: .corpus),
            ]
        )

        let decision = ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: requirement,
            health: health
        )

        #expect(decision.status == .rejected)
        #expect(decision.diagnostics.contains { $0.code == "UNQUALIFIED_REQUIRED_EVIDENCE" })
    }

    @Test func requiredQualifiedEvidenceKindIsRejectedWhenQualificationFailed() {
        let descriptor = makeDescriptor(level: .productionEligible, evidence: [])
        let requirement = makeRequirement(
            minimumLevel: .corpusChecked,
            requiredQualifiedEvidenceKinds: [.corpus]
        )
        let health = ToolHealthCheckResult(
            toolID: descriptor.toolID,
            status: .passed,
            evidence: [
                ToolEvidence(
                    evidenceID: "corpus-1",
                    kind: .corpus,
                    qualification: ToolEvidenceQualificationSummary(
                        qualified: false,
                        observedMetrics: ["passRate": 0.75],
                        failureCodes: ["pass_rate_below_minimum"]
                    )
                ),
            ]
        )

        let decision = ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: requirement,
            health: health
        )

        #expect(decision.status == .rejected)
        #expect(decision.diagnostics.contains { $0.code == "UNQUALIFIED_REQUIRED_EVIDENCE" })
    }

    @Test func requiredQualifiedEvidenceKindRejectsBarePassingFlagWithoutEvaluationSupport() {
        let descriptor = makeDescriptor(level: .corpusChecked, evidence: [])
        let requirement = makeRequirement(
            minimumLevel: .corpusChecked,
            requiredQualifiedEvidenceKinds: [.corpus]
        )
        let health = ToolHealthCheckResult(
            toolID: descriptor.toolID,
            status: .passed,
            evidence: [
                ToolEvidence(
                    evidenceID: "corpus-bare",
                    kind: .corpus,
                    qualification: ToolEvidenceQualificationSummary(qualified: true)
                ),
            ]
        )

        let decision = ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: requirement,
            health: health
        )

        #expect(decision.status == .rejected)
        #expect(decision.diagnostics.contains { $0.code == "UNQUALIFIED_REQUIRED_EVIDENCE" })
    }

    @Test func requiredQualifiedEvidenceKindAllowsPassingTrustProfileEvidence() {
        let descriptor = makeDescriptor(
            level: .corpusChecked,
            evidence: [
                ToolEvidence(
                    evidenceID: "corpus-1",
                    kind: .corpus,
                    qualification: ToolEvidenceQualificationSummary(
                        qualified: true,
                        observedMetrics: [
                            "passRate": 1,
                            "durationBudgetPassRate": 1,
                        ],
                        observedCounts: ["caseCount": 12]
                    )
                ),
            ]
        )
        let requirement = makeRequirement(
            minimumLevel: .corpusChecked,
            requiredQualifiedEvidenceKinds: [.corpus]
        )
        let health = ToolHealthCheckResult(toolID: descriptor.toolID, status: .passed)

        let decision = ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: requirement,
            health: health
        )

        #expect(decision.status == .eligible)
        #expect(!decision.diagnostics.contains { $0.severity == .error })
    }

    @Test func requiredQualifiedEvidenceKindRejectsStalePassingEvidence() {
        let evaluatedAt = Date(timeIntervalSince1970: 1_000)
        let descriptor = makeDescriptor(level: .corpusChecked)
        let requirement = makeRequirement(
            minimumLevel: .corpusChecked,
            requiredQualifiedEvidenceKinds: [.corpus],
            maximumEvidenceAgeSeconds: 60
        )
        let health = ToolHealthCheckResult(
            toolID: descriptor.toolID,
            status: .passed,
            evidence: [
                ToolEvidence(
                    evidenceID: "corpus-1",
                    kind: .corpus,
                    qualification: passingQualificationSummary(),
                    checkedAt: Date(timeIntervalSince1970: 900)
                ),
            ]
        )

        let decision = ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: requirement,
            health: health,
            evaluatedAt: evaluatedAt
        )

        #expect(decision.status == .rejected)
        #expect(decision.diagnostics.contains { $0.code == "STALE_REQUIRED_EVIDENCE" })
        #expect(!decision.diagnostics.contains { $0.code == "UNQUALIFIED_REQUIRED_EVIDENCE" })
    }

    @Test func requiredQualifiedEvidenceKindAllowsFreshPassingEvidence() {
        let evaluatedAt = Date(timeIntervalSince1970: 1_000)
        let descriptor = makeDescriptor(level: .corpusChecked)
        let requirement = makeRequirement(
            minimumLevel: .corpusChecked,
            requiredQualifiedEvidenceKinds: [.corpus],
            maximumEvidenceAgeSeconds: 60
        )
        let health = ToolHealthCheckResult(
            toolID: descriptor.toolID,
            status: .passed,
            evidence: [
                ToolEvidence(
                    evidenceID: "corpus-1",
                    kind: .corpus,
                    qualification: passingQualificationSummary(),
                    checkedAt: Date(timeIntervalSince1970: 960)
                ),
            ]
        )

        let decision = ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: requirement,
            health: health,
            evaluatedAt: evaluatedAt
        )

        #expect(decision.status == .eligible)
        #expect(!decision.diagnostics.contains { $0.severity == .error })
    }

    @Test func requiredEvidenceKindRejectsMissingTimestampWhenFreshnessIsRequired() {
        let evaluatedAt = Date(timeIntervalSince1970: 1_000)
        let descriptor = makeDescriptor(level: .corpusChecked)
        let requirement = makeRequirement(
            minimumLevel: .corpusChecked,
            requiredEvidenceKinds: [.corpus],
            maximumEvidenceAgeSeconds: 60
        )
        let health = ToolHealthCheckResult(
            toolID: descriptor.toolID,
            status: .passed,
            evidence: [
                ToolEvidence(evidenceID: "corpus-1", kind: .corpus),
            ]
        )

        let decision = ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: requirement,
            health: health,
            evaluatedAt: evaluatedAt
        )

        #expect(decision.status == .rejected)
        #expect(decision.diagnostics.contains { $0.code == "STALE_REQUIRED_EVIDENCE" })
    }

    @Test func futureCheckedAtIsRejectedWithExplicitFutureDiagnostic() {
        let evaluatedAt = Date(timeIntervalSince1970: 1_000)
        let descriptor = makeDescriptor(level: .corpusChecked)
        let requirement = makeRequirement(
            minimumLevel: .corpusChecked,
            requiredEvidenceKinds: [.corpus],
            maximumEvidenceAgeSeconds: 60
        )
        let health = ToolHealthCheckResult(
            toolID: descriptor.toolID,
            status: .passed,
            evidence: [
                ToolEvidence(
                    evidenceID: "corpus-1",
                    kind: .corpus,
                    qualification: passingQualificationSummary(),
                    checkedAt: Date(timeIntervalSince1970: 2_000)
                ),
            ]
        )

        let decision = ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: requirement,
            health: health,
            evaluatedAt: evaluatedAt
        )

        #expect(decision.status == .rejected)
        let staleDiagnostic = decision.diagnostics.first { $0.code == "STALE_REQUIRED_EVIDENCE" }
        #expect(staleDiagnostic != nil)
        #expect(staleDiagnostic?.message.contains("checkedAt is in the future") == true)
        #expect(staleDiagnostic?.message.contains("1970-01-01T00:33:20Z") == true)
    }

    @Test func invalidEvidenceFreshnessRequirementIsRejected() {
        let descriptor = makeDescriptor(level: .productionEligible)
        let requirement = makeRequirement(
            minimumLevel: .corpusChecked,
            requiredEvidenceKinds: [.corpus],
            maximumEvidenceAgeSeconds: -1
        )
        let health = ToolHealthCheckResult(
            toolID: descriptor.toolID,
            status: .passed,
            evidence: [
                ToolEvidence(evidenceID: "corpus-1", kind: .corpus),
            ]
        )

        let decision = ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: requirement,
            health: health
        )

        #expect(decision.status == .rejected)
        #expect(decision.diagnostics.contains {
            $0.code == "INVALID_EVIDENCE_FRESHNESS_REQUIREMENT"
        })
    }

    @Test func requirementJSONRejectsMissingEvidenceFields() throws {
        let json = """
        {
          "kind": "drc",
          "operationID": "run-drc",
          "minimumLevel": "corpusChecked",
          "requiredInputFormats": ["OASIS"],
          "requiredOutputFormats": ["JSON"]
        }
        """

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                ToolTrustRequirement.self,
                from: Data(json.utf8)
            )
        }
    }

    @Test func requirementJSONDecodesEvidenceFreshness() throws {
        let json = """
        {
          "kind": "drc",
          "operationID": "run-drc",
          "minimumLevel": "corpusChecked",
          "requiredInputFormats": ["OASIS"],
          "requiredOutputFormats": ["JSON"],
          "requiredEvidenceKinds": ["corpus"],
          "requiredQualifiedEvidenceKinds": ["oracle"],
          "maximumEvidenceAgeSeconds": 3600,
          "requirePassingHealthCheck": true
        }
        """

        let requirement = try JSONDecoder().decode(
            ToolTrustRequirement.self,
            from: Data(json.utf8)
        )

        #expect(requirement.requiredEvidenceKinds == [.corpus])
        #expect(requirement.requiredQualifiedEvidenceKinds == [.oracle])
        #expect(requirement.maximumEvidenceAgeSeconds == 3_600)
    }

    private func makeRequirement(
        minimumLevel: ToolQualificationLevel,
        requiredEvidenceKinds: [ToolEvidenceKind] = [],
        requiredQualifiedEvidenceKinds: [ToolEvidenceKind] = [],
        maximumEvidenceAgeSeconds: TimeInterval? = nil
    ) -> ToolTrustRequirement {
        ToolTrustRequirement(
            kind: .drc,
            operationID: "run-drc",
            minimumLevel: minimumLevel,
            requiredInputFormats: [.oasis],
            requiredOutputFormats: [.json],
            requiredEvidenceKinds: requiredEvidenceKinds,
            requiredQualifiedEvidenceKinds: requiredQualifiedEvidenceKinds,
            maximumEvidenceAgeSeconds: maximumEvidenceAgeSeconds
        )
    }

    @Test func qualificationScopeMustMatchRequestedBuildAndDeck() {
        let observedScope = ToolQualificationScope(
            implementationID: "native-lvs",
            binaryDigest: "build-a",
            algorithmVersion: "graph-v2",
            processProfileID: "sky130A",
            deckDigest: "deck-a"
        )
        let requiredScope = ToolQualificationScope(
            implementationID: "native-lvs",
            binaryDigest: "build-b",
            algorithmVersion: "graph-v2",
            processProfileID: "sky130A",
            deckDigest: "deck-a"
        )
        let evidence = ToolEvidence(
            evidenceID: "scoped-corpus",
            kind: .corpus,
            qualification: ToolEvidenceQualificationSummary(
                qualified: true,
                policyID: "production-lvs",
                observedMetrics: ["passRate": 1],
                observedCounts: ["caseCount": 100],
                scope: observedScope
            )
        )
        let descriptor = makeDescriptor(level: .corpusChecked, evidence: [evidence])
        let requirement = ToolTrustRequirement(
            kind: .drc,
            operationID: "run-drc",
            minimumLevel: .corpusChecked,
            requiredInputFormats: [.oasis],
            requiredOutputFormats: [.json],
            qualificationScope: requiredScope
        )
        let decision = ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: requirement,
            health: ToolHealthCheckResult(toolID: descriptor.toolID, status: .passed)
        )

        #expect(decision.status == .rejected)
        #expect(decision.diagnostics.contains { $0.code == "UNQUALIFIED_REQUIRED_EVIDENCE" })
    }

    @Test func independentQualificationEvidenceIsRequiredWhenRequested() {
        let descriptor = makeDescriptor(
            level: .productionEligible,
            evidence: [
                ToolEvidence(
                    evidenceID: "production-approval",
                    kind: .productionApproval,
                    qualification: ToolEvidenceQualificationSummary(
                        qualified: true,
                        scope: ToolQualificationScope(
                            implementationID: "native-drc",
                            binaryDigest: "binary",
                            algorithmVersion: "algorithm",
                            processProfileID: "process",
                            deckDigest: "deck"
                        )
                    )
                )
            ]
        )
        let requirement = ToolTrustRequirement(
            kind: .drc,
            operationID: "run-drc",
            minimumLevel: .productionEligible,
            requiredEvidenceKinds: [.productionApproval],
            requiredQualifiedEvidenceKinds: [.productionApproval],
            qualificationScope: ToolQualificationScope(
                implementationID: "native-drc",
                binaryDigest: "binary",
                algorithmVersion: "algorithm",
                processProfileID: "process",
                deckDigest: "deck"
            ),
            requireIndependentQualificationEvidence: true
        )

        let decision = ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: requirement,
            health: ToolHealthCheckResult(toolID: descriptor.toolID, status: .passed)
        )

        #expect(decision.status == .rejected)
        #expect(decision.diagnostics.contains { $0.code == "UNQUALIFIED_REQUIRED_EVIDENCE" })
    }

    @Test func processQualificationEvidenceRequiresIndependentScopedEvidence() {
        let scope = ToolQualificationScope(
            implementationID: "native-drc",
            binaryDigest: String(repeating: "a", count: 64),
            algorithmVersion: "native-drc-v2",
            processProfileID: "sky130",
            deckDigest: String(repeating: "b", count: 64),
            pdkID: "sky130A",
            pdkDigest: String(repeating: "c", count: 64)
        )
        let evidence = ToolProcessQualificationEvidence(
            qualificationID: "sky130-drc-production",
            toolID: "native-drc",
            scope: scope,
            status: .qualified,
            corpusEvidenceIDs: ["corpus-1"],
            oracleEvidenceIDs: ["oracle-1"],
            healthEvidenceIDs: ["health-1"],
            approvalEvidenceIDs: ["approval-1"],
            evidenceArtifactIDs: ["record.json"],
            independenceVerified: true,
            qualifiedAt: Date(timeIntervalSince1970: 100),
            expiresAt: Date(timeIntervalSince1970: 200)
        )

        #expect(evidence.isStructurallyValid)
        #expect(evidence.isQualified(at: Date(timeIntervalSince1970: 150), requirePDKScope: true))
        #expect(!evidence.isQualified(at: Date(timeIntervalSince1970: 250), requirePDKScope: true))
        let summary = evidence.summary(policyID: "release-policy")
        #expect(summary.qualificationID == "sky130-drc-production")
        #expect(summary.independenceVerified)
        #expect(summary.scope == scope)
    }

    private func makeDescriptor(
        level: ToolQualificationLevel,
        evidence: [ToolEvidence]? = nil,
        capabilities: [ToolCapability] = [
            ToolCapability(
                operationID: "run-drc",
                inputFormats: [.oasis, .gdsii],
                outputFormats: [.json]
            ),
        ]
    ) -> ToolDescriptor {
        ToolDescriptor(
            toolID: "native-drc",
            displayName: "Native DRC",
            kind: .drc,
            version: "1.0.0",
            capabilities: capabilities,
            trustProfile: ToolTrustProfile(
                level: level,
                evidence: evidence ?? evidenceSupporting(level: level)
            ),
            environment: ToolEnvironment(platform: "macOS", requiredAssets: [])
        )
    }

    private func evidenceSupporting(level: ToolQualificationLevel) -> [ToolEvidence] {
        switch level {
        case .unknown:
            return []
        case .smokeChecked:
            return [qualifiedEvidence("smoke-1", kind: .smoke)]
        case .corpusChecked:
            return [qualifiedEvidence("corpus-1", kind: .corpus)]
        case .oracleChecked:
            return [
                qualifiedEvidence("corpus-1", kind: .corpus),
                qualifiedEvidence("oracle-1", kind: .oracle),
            ]
        case .productionEligible:
            return [
                qualifiedEvidence("corpus-1", kind: .corpus),
                qualifiedEvidence("oracle-1", kind: .oracle),
                qualifiedEvidence("production-approval-1", kind: .productionApproval),
            ]
        }
    }

    private func qualifiedEvidence(_ evidenceID: String, kind: ToolEvidenceKind) -> ToolEvidence {
        ToolEvidence(
            evidenceID: evidenceID,
            kind: kind,
            qualification: passingQualificationSummary()
        )
    }

    private func passingQualificationSummary() -> ToolEvidenceQualificationSummary {
        ToolEvidenceQualificationSummary(
            qualified: true,
            policyID: "unit-test-policy",
            observedMetrics: ["passRate": 1],
            observedCounts: ["caseCount": 1]
        )
    }
}
