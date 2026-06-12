import Foundation

public struct ToolTrustDecision: Sendable, Hashable, Codable {
    public var toolID: String
    public var status: ToolTrustDecisionStatus
    public var diagnostics: [ToolDiagnostic]

    public init(
        toolID: String,
        status: ToolTrustDecisionStatus,
        diagnostics: [ToolDiagnostic] = []
    ) {
        self.toolID = toolID
        self.status = status
        self.diagnostics = diagnostics
    }
}
