import Foundation
import Testing
import ToolQualification

@Suite
struct DefaultToolQualificationEngineTests {
    @Test
    func returnsEligibleDecisionAndFoundationProvenance() async throws {
        let evaluatedAt = Date(timeIntervalSince1970: 100)
        let descriptor = ToolDescriptor(
            toolID: "simulator",
            displayName: "Simulator",
            kind: .simulation,
            version: "1.0.0",
            capabilities: [ToolCapability(operationID: "simulate")],
            trustProfile: ToolTrustProfile(level: .unknown),
            environment: ToolEnvironment(platform: "macOS")
        )
        let request = ToolQualificationRequest(
            descriptor: descriptor,
            requirement: ToolTrustRequirement(
                kind: .simulation,
                operationID: "simulate",
                minimumLevel: .unknown
            ),
            health: ToolHealthCheckResult(toolID: descriptor.toolID, status: .passed),
            evaluatedAt: evaluatedAt
        )
        let producer = try ProducerIdentity(
            kind: .library,
            identifier: "ToolQualification",
            version: "1.0.0"
        )
        let engine = DefaultToolQualificationEngine(
            artifactReader: UnusedArtifactReader(),
            producer: producer,
            completionDate: { Date(timeIntervalSince1970: 101) }
        )

        let result = try await engine.execute(request)

        #expect(result.decision.status == .eligible)
        #expect(result.diagnostics.isEmpty)
        #expect(result.artifacts.isEmpty)
        #expect(result.evidence.provenance.producer == producer)
        #expect(result.evidence.provenance.startedAt == evaluatedAt)
        #expect(result.evidence.provenance.completedAt == Date(timeIntervalSince1970: 101))
    }

    @Test
    func preservesHealthDiagnosticsAsFoundationDiagnostics() async throws {
        let descriptor = ToolDescriptor(
            toolID: "simulator",
            displayName: "Simulator",
            kind: .simulation,
            version: "1.0.0",
            capabilities: [ToolCapability(operationID: "simulate")],
            trustProfile: ToolTrustProfile(level: .unknown),
            environment: ToolEnvironment(platform: "macOS")
        )
        let health = ToolHealthCheckResult(
            toolID: descriptor.toolID,
            status: .failed,
            diagnostics: [
                ToolDiagnostic(
                    severity: .error,
                    code: "SMOKE_FAILED",
                    message: "Smoke fixture failed."
                )
            ]
        )
        let request = ToolQualificationRequest(
            descriptor: descriptor,
            requirement: ToolTrustRequirement(
                kind: .simulation,
                operationID: "simulate",
                minimumLevel: .unknown
            ),
            health: health,
            evaluatedAt: Date(timeIntervalSince1970: 100)
        )
        let engine = DefaultToolQualificationEngine(
            artifactReader: UnusedArtifactReader(),
            producer: try ProducerIdentity(
                kind: .library,
                identifier: "ToolQualification",
                version: "1.0.0"
            ),
            completionDate: { Date(timeIntervalSince1970: 101) }
        )

        let result = try await engine.execute(request)

        #expect(result.decision.status == .rejected)
        #expect(
            result.diagnostics.contains {
                $0.code.rawValue == "toolqualification.health.SMOKE_FAILED"
            }
        )
        #expect(
            result.diagnostics.contains {
                $0.code.rawValue == "toolqualification.HEALTH_CHECK_FAILED"
            }
        )
    }

    @Test
    func rejectsAnUnrepresentableDiagnosticCode() async throws {
        let descriptor = ToolDescriptor(
            toolID: "simulator",
            displayName: "Simulator",
            kind: .simulation,
            version: "1.0.0",
            capabilities: [ToolCapability(operationID: "simulate")],
            trustProfile: ToolTrustProfile(level: .unknown),
            environment: ToolEnvironment(platform: "macOS")
        )
        let request = ToolQualificationRequest(
            descriptor: descriptor,
            requirement: ToolTrustRequirement(
                kind: .simulation,
                operationID: "simulate",
                minimumLevel: .unknown
            ),
            health: ToolHealthCheckResult(
                toolID: descriptor.toolID,
                status: .failed,
                diagnostics: [ToolDiagnostic(severity: .error, code: "", message: "Invalid code")]
            ),
            evaluatedAt: Date(timeIntervalSince1970: 100)
        )
        let engine = DefaultToolQualificationEngine(
            artifactReader: UnusedArtifactReader(),
            producer: try ProducerIdentity(
                kind: .library,
                identifier: "ToolQualification",
                version: "1.0.0"
            ),
            completionDate: { Date(timeIntervalSince1970: 101) }
        )

        await #expect(throws: ToolQualificationEngineError.invalidDiagnosticCode("")) {
            try await engine.execute(request)
        }
    }
}

private struct UnusedArtifactReader: ToolQualificationArtifactReading {
    func verifiedData(for reference: ArtifactReference) async throws -> Data {
        throw ToolProcessQualificationEvidenceBuildError.invalidInput(
            "Unexpected artifact read for \(reference.id.rawValue)."
        )
    }
}
