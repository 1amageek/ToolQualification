import CircuiteFoundation
import Foundation

public protocol ToolQualificationRecordIssuing: Sendable {
    func issue(
        recordID: String,
        descriptor: ToolDescriptor,
        health: ToolHealthCheckResult,
        issuer: ProducerIdentity,
        reading artifacts: any ToolQualificationArtifactReading,
        issuedAt: Date
    ) async throws -> ToolQualificationRecord
}
