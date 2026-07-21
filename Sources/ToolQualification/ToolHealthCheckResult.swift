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

    public var isStructurallyValid: Bool {
        !toolID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && diagnostics.allSatisfy {
                !$0.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !$0.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            && evidence.allSatisfy(\.isStructurallyValid)
            && Set(evidence.map(\.evidenceID)).count == evidence.count
            && (status != .passed || !diagnostics.contains { $0.severity == .error })
    }
}
