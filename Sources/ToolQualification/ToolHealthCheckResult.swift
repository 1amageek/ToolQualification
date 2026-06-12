import Foundation

public struct ToolHealthCheckResult: Sendable, Hashable, Codable {
    public var toolID: String
    public var status: ToolHealthStatus
    public var diagnostics: [ToolDiagnostic]
    public var evidence: [ToolEvidence]

    public init(
        toolID: String,
        status: ToolHealthStatus,
        diagnostics: [ToolDiagnostic] = [],
        evidence: [ToolEvidence] = []
    ) {
        self.toolID = toolID
        self.status = status
        self.diagnostics = diagnostics
        self.evidence = evidence
    }
}
