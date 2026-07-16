import Testing
import ToolQualification

@Suite("Tool registry")
struct ToolRegistryTests {
    @Test func upsertReplacesDescriptorByToolID() throws {
        var registry = ToolRegistry(descriptors: [
            makeDescriptor(toolID: "drc", level: .unknown),
        ])

        try registry.upsert(makeDescriptor(toolID: "drc", level: .smokeChecked))

        #expect(registry.descriptor(toolID: "drc")?.trustProfile.level == .smokeChecked)
    }

    @Test func upsertRejectsInvalidToolID() {
        var registry = ToolRegistry()

        #expect(throws: ToolQualificationError.invalidToolID("../drc")) {
            try registry.upsert(makeDescriptor(toolID: "../drc", level: .unknown))
        }
    }

    @Test func deterministicTieBreakUsesToolID() async {
        let registry = ToolRegistry(descriptors: [
            makeDescriptor(toolID: "z-tool", level: .smokeChecked),
            makeDescriptor(toolID: "a-tool", level: .smokeChecked),
        ])
        let health = [
            "a-tool": ToolHealthCheckResult(toolID: "a-tool", status: .passed),
            "z-tool": ToolHealthCheckResult(toolID: "z-tool", status: .passed),
        ]

        let selected = await registry.select(
            requirement: makeRequirement(),
            healthResults: health
        )

        #expect(selected?.toolID == "a-tool")
    }

    @Test func selectPrefersTheMostQualifiedEligibleCandidate() async {
        let registry = ToolRegistry(descriptors: [
            makeDescriptor(toolID: "unknown-tool", level: .unknown),
            makeDescriptor(toolID: "smoke-tool", level: .smokeChecked),
        ])
        let health = [
            "unknown-tool": ToolHealthCheckResult(toolID: "unknown-tool", status: .passed),
            "smoke-tool": ToolHealthCheckResult(toolID: "smoke-tool", status: .passed),
        ]
        let requirement = ToolTrustRequirement(
            kind: .drc,
            operationID: "run-drc",
            minimumLevel: .unknown,
            requiredInputFormats: [.oasis],
            requiredOutputFormats: [.json]
        )

        let selected = await registry.select(requirement: requirement, healthResults: health)

        #expect(selected?.toolID == "smoke-tool")
    }

    @Test func selectSkipsFailedHealthCandidates() async {
        let registry = ToolRegistry(descriptors: [
            makeDescriptor(toolID: "failed", level: .smokeChecked),
            makeDescriptor(toolID: "healthy", level: .smokeChecked),
        ])
        let health = [
            "failed": ToolHealthCheckResult(toolID: "failed", status: .failed),
            "healthy": ToolHealthCheckResult(toolID: "healthy", status: .passed),
        ]

        let selected = await registry.select(
            requirement: makeRequirement(),
            healthResults: health
        )

        #expect(selected?.toolID == "healthy")
    }

    @Test func registryFailsClosedWhenQualifiedEvidenceCannotBeRead() async {
        let registry = ToolRegistry(descriptors: [
            makeDescriptor(
                toolID: "corpus-tool",
                level: .corpusChecked,
                evidence: [ToolEvidence(evidenceID: "corpus", kind: .corpus)]
            ),
        ])

        let selected = await registry.select(
            requirement: ToolTrustRequirement(
                kind: .drc,
                operationID: "run-drc",
                minimumLevel: .corpusChecked,
                requiredInputFormats: [.oasis],
                requiredOutputFormats: [.json]
            ),
            healthResults: [
                "corpus-tool": ToolHealthCheckResult(toolID: "corpus-tool", status: .passed),
            ]
        )

        #expect(selected == nil)
    }

    @Test func validatingInitializerRejectsDuplicateToolIDs() {
        #expect(throws: ToolQualificationError.self) {
            try ToolRegistry(validating: [
                makeDescriptor(toolID: "drc", level: .unknown),
                makeDescriptor(toolID: "drc", level: .smokeChecked),
            ])
        }
    }

    private func makeRequirement() -> ToolTrustRequirement {
        ToolTrustRequirement(
            kind: .drc,
            operationID: "run-drc",
            minimumLevel: .smokeChecked,
            requiredInputFormats: [.oasis],
            requiredOutputFormats: [.json]
        )
    }

    private func makeDescriptor(
        toolID: String,
        level: ToolQualificationLevel,
        evidence: [ToolEvidence] = []
    ) -> ToolDescriptor {
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
            trustProfile: ToolTrustProfile(level: level, evidence: evidence),
            environment: ToolEnvironment(platform: "macOS", requiredAssets: [])
        )
    }
}
