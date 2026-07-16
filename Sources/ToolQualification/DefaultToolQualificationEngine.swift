import CircuiteFoundation
import Foundation

public struct DefaultToolQualificationEngine: ToolQualificationEngine {
    private let evaluator: ToolTrustEvaluator
    private let artifactReader: any ToolQualificationArtifactReading
    private let producer: ProducerIdentity
    private let completionDate: @Sendable () -> Date

    public init(
        evaluator: ToolTrustEvaluator = ToolTrustEvaluator(),
        artifactReader: any ToolQualificationArtifactReading,
        producer: ProducerIdentity,
        completionDate: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.evaluator = evaluator
        self.artifactReader = artifactReader
        self.producer = producer
        self.completionDate = completionDate
    }

    public func execute(
        _ request: ToolQualificationRequest
    ) async throws -> ToolQualificationResult {
        try Task.checkCancellation()

        let decision = await evaluator.evaluate(
            descriptor: request.descriptor,
            requirement: request.requirement,
            health: request.health,
            artifactReader: artifactReader,
            evaluatedAt: request.evaluatedAt
        )
        let diagnostics = try foundationDiagnostics(
            decision: decision,
            health: request.health
        )
        let provenance = try ExecutionProvenance(
            producer: producer,
            inputs: request.inputs,
            startedAt: request.evaluatedAt,
            completedAt: completionDate()
        )

        try Task.checkCancellation()

        return ToolQualificationResult(
            decision: decision,
            artifacts: [],
            diagnostics: diagnostics,
            provenance: provenance
        )
    }

    private func foundationDiagnostics(
        decision: ToolTrustDecision,
        health: ToolHealthCheckResult?
    ) throws -> [DesignDiagnostic] {
        let decisionDiagnostics = try decision.diagnostics.map {
            try foundationDiagnostic($0, prefix: "toolqualification")
        }
        let healthDiagnostics = try (health?.diagnostics ?? []).map {
            try foundationDiagnostic($0, prefix: "toolqualification.health")
        }
        return decisionDiagnostics + healthDiagnostics
    }

    private func foundationDiagnostic(
        _ diagnostic: ToolDiagnostic,
        prefix: String
    ) throws -> DesignDiagnostic {
        guard !diagnostic.code.isEmpty else {
            throw ToolQualificationEngineError.invalidDiagnosticCode(diagnostic.code)
        }

        let code: DiagnosticCode
        do {
            _ = try DiagnosticCode(rawValue: diagnostic.code)
            code = try DiagnosticCode(rawValue: "\(prefix).\(diagnostic.code)")
        } catch {
            throw ToolQualificationEngineError.invalidDiagnosticCode(diagnostic.code)
        }

        let suggestedActions: [SuggestedAction]
        switch diagnostic.severity {
        case .error:
            suggestedActions = [
                SuggestedAction(
                    code: "review-tool-qualification",
                    summary: "Review the tool qualification evidence and trust requirements."
                )
            ]
        case .info, .warning:
            suggestedActions = []
        }

        return DesignDiagnostic(
            code: code,
            severity: foundationSeverity(for: diagnostic.severity),
            summary: diagnostic.message,
            detail: "Tool diagnostic code: \(diagnostic.code)",
            suggestedActions: suggestedActions
        )
    }

    private func foundationSeverity(
        for severity: ToolDiagnosticSeverity
    ) -> DiagnosticSeverity {
        switch severity {
        case .info:
            .information
        case .warning:
            .warning
        case .error:
            .error
        }
    }
}
