import Foundation
import ToolQualification

/// stdout contract for `toolqualification validate-process-evidence`.
public struct ToolQualificationProcessEvidenceEnvelope: Sendable, Equatable, Codable {
    public var command: String
    public var evidencePath: String
    public var qualificationID: String
    public var toolID: String
    public var status: ToolProcessQualificationStatus
    public var structurallyValid: Bool
    public var qualified: Bool
    public var requirePDKScope: Bool
    public var scope: ToolQualificationScope
    public var qualifiedAt: String?
    public var expiresAt: String?
    public var evaluatedAt: String
    public var diagnostics: [String]

    public init(
        command: String = "validate-process-evidence",
        evidencePath: String,
        qualificationID: String,
        toolID: String,
        status: ToolProcessQualificationStatus,
        structurallyValid: Bool,
        qualified: Bool,
        requirePDKScope: Bool,
        scope: ToolQualificationScope,
        qualifiedAt: String?,
        expiresAt: String?,
        evaluatedAt: String,
        diagnostics: [String]
    ) {
        self.command = command
        self.evidencePath = evidencePath
        self.qualificationID = qualificationID
        self.toolID = toolID
        self.status = status
        self.structurallyValid = structurallyValid
        self.qualified = qualified
        self.requirePDKScope = requirePDKScope
        self.scope = scope
        self.qualifiedAt = qualifiedAt
        self.expiresAt = expiresAt
        self.evaluatedAt = evaluatedAt
        self.diagnostics = diagnostics
    }
}
