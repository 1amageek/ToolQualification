import Foundation

public protocol ToolTrustEvaluating: Sendable {
    func evaluate(
        descriptor: ToolDescriptor,
        requirement: ToolTrustRequirement,
        health: ToolHealthCheckResult?,
        artifactReader: (any ToolQualificationArtifactReading)?,
        evaluatedAt: Date
    ) async -> ToolTrustDecision
}

public extension ToolTrustEvaluating {
    func evaluate(
        descriptor: ToolDescriptor,
        requirement: ToolTrustRequirement,
        health: ToolHealthCheckResult?,
        artifactReader: (any ToolQualificationArtifactReading)? = nil
    ) async -> ToolTrustDecision {
        await evaluate(
            descriptor: descriptor,
            requirement: requirement,
            health: health,
            artifactReader: artifactReader,
            evaluatedAt: Date()
        )
    }
}
