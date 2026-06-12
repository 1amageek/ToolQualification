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

    private func makeRequirement(minimumLevel: ToolQualificationLevel) -> ToolTrustRequirement {
        ToolTrustRequirement(
            kind: .drc,
            operationID: "run-drc",
            minimumLevel: minimumLevel,
            requiredInputFormats: [.oasis],
            requiredOutputFormats: [.json]
        )
    }

    private func makeDescriptor(
        level: ToolQualificationLevel,
        capabilities: [ToolCapability] = [
            ToolCapability(
                operationID: "run-drc",
                inputFormats: [.oasis, .gdsii],
                outputFormats: [.json]
            ),
        ]
    ) -> ToolDescriptor {
        ToolDescriptor(
            toolID: "pure-swift-drc",
            displayName: "Pure Swift DRC",
            kind: .drc,
            version: "1.0.0",
            capabilities: capabilities,
            trustProfile: ToolTrustProfile(level: level),
            environment: ToolEnvironment(platform: "macOS", requiredAssets: [])
        )
    }
}
