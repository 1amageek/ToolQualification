import Testing
import ToolQualification
import XcircuitePackage

@Suite("Tool registry")
struct ToolRegistryTests {
    @Test func upsertReplacesDescriptorByToolID() {
        var registry = ToolRegistry(descriptors: [
            makeDescriptor(toolID: "drc", level: .smokeChecked),
        ])

        registry.upsert(makeDescriptor(toolID: "drc", level: .productionEligible))

        #expect(registry.descriptor(toolID: "drc")?.trustProfile.level == .productionEligible)
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

    @Test func defaultInitializerDoesNotTrapOnDuplicateToolIDs() {
        let registry = ToolRegistry(descriptors: [
            makeDescriptor(toolID: "drc", level: .smokeChecked),
            makeDescriptor(toolID: "drc", level: .productionEligible),
        ])

        #expect(registry.descriptor(toolID: "drc")?.trustProfile.level == .productionEligible)
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
            trustProfile: ToolTrustProfile(level: level),
            environment: ToolEnvironment(platform: "macOS", requiredAssets: [])
        )
    }
}
