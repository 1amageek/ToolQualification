import CircuiteFoundation
import Foundation

public struct ToolQualificationRecordValidator: ToolQualificationRecordValidating {
    private let evaluator: any ToolTrustEvaluating

    public init(evaluator: any ToolTrustEvaluating = ToolTrustEvaluator()) {
        self.evaluator = evaluator
    }

    public func validatedRecord(
        referencedBy artifact: ArtifactReference,
        expectedToolID: String,
        reading artifacts: any ToolQualificationArtifactReading
    ) async throws -> ToolQualificationRecord {
        let record = try ToolQualificationRecord.decodeCanonical(
            from: try await artifacts.verifiedData(for: artifact)
        )
        return try await validatedRecord(
            record,
            expectedToolID: expectedToolID,
            reading: artifacts
        )
    }

    public func validatedRecord(
        _ record: ToolQualificationRecord,
        expectedToolID: String,
        reading artifacts: any ToolQualificationArtifactReading
    ) async throws -> ToolQualificationRecord {
        guard record.descriptor.toolID == expectedToolID else {
            throw ToolQualificationRecordError.toolIdentityMismatch(
                expected: expectedToolID,
                actual: record.descriptor.toolID
            )
        }
        for capability in record.descriptor.capabilities.sorted(by: { $0.operationID < $1.operationID }) {
            let requirement = ToolTrustRequirement.qualificationRecordRequirement(
                descriptor: record.descriptor,
                operationID: capability.operationID
            )
            let decision = await evaluator.evaluate(
                descriptor: record.descriptor,
                requirement: requirement,
                health: record.health,
                artifactReader: artifacts,
                evaluatedAt: record.issuedAt
            )
            guard decision.status == .eligible,
                  record.issuanceDecisions.contains(where: {
                      $0.operationID == capability.operationID && $0.decision == decision
                  }) else {
                throw ToolQualificationRecordError.issuanceDecisionMismatch(
                    operationID: capability.operationID
                )
            }
        }
        return record
    }
}
