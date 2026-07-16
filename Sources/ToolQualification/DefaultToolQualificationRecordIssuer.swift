import CircuiteFoundation
import Foundation

public struct DefaultToolQualificationRecordIssuer: ToolQualificationRecordIssuing {
    private let evaluator: any ToolTrustEvaluating

    public init(evaluator: any ToolTrustEvaluating = ToolTrustEvaluator()) {
        self.evaluator = evaluator
    }

    public func issue(
        recordID: String,
        descriptor: ToolDescriptor,
        health: ToolHealthCheckResult,
        issuer: ProducerIdentity,
        reading artifacts: any ToolQualificationArtifactReading,
        issuedAt: Date
    ) async throws -> ToolQualificationRecord {
        guard health.toolID == descriptor.toolID,
              !descriptor.capabilities.isEmpty else {
            throw ToolQualificationRecordError.invalidStructure
        }

        var decisions: [ToolQualificationRecordDecision] = []
        for capability in descriptor.capabilities.sorted(by: { $0.operationID < $1.operationID }) {
            let requirement = ToolTrustRequirement(
                kind: descriptor.kind,
                operationID: capability.operationID,
                minimumLevel: descriptor.trustProfile.level,
                requirePassingHealthCheck: true
            )
            let decision = await evaluator.evaluate(
                descriptor: descriptor,
                requirement: requirement,
                health: health,
                artifactReader: artifacts,
                evaluatedAt: issuedAt
            )
            guard decision.status == .eligible else {
                throw ToolQualificationRecordError.issuanceRejected(
                    toolID: descriptor.toolID,
                    operationID: capability.operationID
                )
            }
            decisions.append(ToolQualificationRecordDecision(
                operationID: capability.operationID,
                decision: decision
            ))
        }

        return ToolQualificationRecord(
            recordID: recordID,
            descriptor: descriptor,
            health: health,
            issuanceDecisions: decisions,
            issuer: issuer,
            issuedAt: issuedAt
        )
    }
}
