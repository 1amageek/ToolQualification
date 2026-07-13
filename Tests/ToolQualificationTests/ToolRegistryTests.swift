import Testing
import ToolQualification

@Suite("Tool registry")
struct ToolRegistryTests {
    @Test func upsertReplacesDescriptorByToolID() throws {
        var registry = ToolRegistry(descriptors: [
            makeDescriptor(toolID: "drc", level: .smokeChecked),
        ])

        try registry.upsert(makeDescriptor(toolID: "drc", level: .productionEligible))

        #expect(registry.descriptor(toolID: "drc")?.trustProfile.level == .productionEligible)
    }

    @Test func upsertRejectsInvalidToolID() {
        var registry = ToolRegistry()

        #expect(throws: ToolQualificationError.invalidToolID("../drc")) {
            try registry.upsert(makeDescriptor(toolID: "../drc", level: .smokeChecked))
        }
    }

    @Test func selectReturnsMostQualifiedEligibleCandidate() {
        let registry = ToolRegistry(descriptors: [
            makeDescriptor(toolID: "b-tool", level: .corpusChecked),
            makeDescriptor(toolID: "a-tool", level: .productionEligible),
        ])
        let health = [
            "a-tool": ToolHealthCheckResult(toolID: "a-tool", status: .passed),
            "b-tool": ToolHealthCheckResult(toolID: "b-tool", status: .passed),
        ]

        let selected = registry.select(
            requirement: makeRequirement(),
            healthResults: health
        )

        #expect(selected?.toolID == "a-tool")
    }

    @Test func selectSkipsFailedHealthCandidates() {
        let registry = ToolRegistry(descriptors: [
            makeDescriptor(toolID: "better-but-failed", level: .productionEligible),
            makeDescriptor(toolID: "lower-but-healthy", level: .corpusChecked),
        ])
        let health = [
            "better-but-failed": ToolHealthCheckResult(toolID: "better-but-failed", status: .failed),
            "lower-but-healthy": ToolHealthCheckResult(toolID: "lower-but-healthy", status: .passed),
        ]

        let selected = registry.select(
            requirement: makeRequirement(),
            healthResults: health
        )

        #expect(selected?.toolID == "lower-but-healthy")
    }

    @Test func deterministicTieBreakUsesToolID() {
        let registry = ToolRegistry(descriptors: [
            makeDescriptor(toolID: "z-tool", level: .corpusChecked),
            makeDescriptor(toolID: "a-tool", level: .corpusChecked),
        ])
        let health = [
            "a-tool": ToolHealthCheckResult(toolID: "a-tool", status: .passed),
            "z-tool": ToolHealthCheckResult(toolID: "z-tool", status: .passed),
        ]

        let selected = registry.select(
            requirement: makeRequirement(),
            healthResults: health
        )

        #expect(selected?.toolID == "a-tool")
    }

    @Test func validatingInitializerRejectsDuplicateToolIDs() {
        #expect(throws: ToolQualificationError.self) {
            try ToolRegistry(validating: [
                makeDescriptor(toolID: "drc", level: .smokeChecked),
                makeDescriptor(toolID: "drc", level: .productionEligible),
            ])
        }
    }

    @Test func replaceUncheckedIsExplicitDuplicateReplacementPath() {
        let registry = ToolRegistry(descriptors: [
            makeDescriptor(toolID: "drc", level: .smokeChecked),
        ])
        var mutable = registry
        mutable.replaceUnchecked(makeDescriptor(toolID: "drc", level: .productionEligible))

        #expect(mutable.descriptor(toolID: "drc")?.trustProfile.level == .productionEligible)
    }

    private func makeRequirement() -> ToolTrustRequirement {
        ToolTrustRequirement(
            kind: .drc,
            operationID: "run-drc",
            minimumLevel: .corpusChecked,
            requiredInputFormats: [.oasis],
            requiredOutputFormats: [.json]
        )
    }

    private func makeDescriptor(toolID: String, level: ToolQualificationLevel) -> ToolDescriptor {
        ToolDescriptor(
            toolID: toolID,
            displayName: toolID,
            kind: .drc,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "run-drc",
                    inputFormats: [.oasis],
                    outputFormats: [.json]
                ),
            ],
            trustProfile: ToolTrustProfile(level: level, evidence: evidenceSupporting(level: level)),
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
            qualification: ToolEvidenceQualificationSummary(
                qualified: true,
                policyID: "unit-test-policy",
                observedMetrics: ["passRate": 1],
                observedCounts: ["caseCount": 1]
            )
        )
    }
}
