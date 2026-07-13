import Foundation
import ToolQualification

public struct ToolQualificationBuildProcessEvidenceEnvelope: Sendable, Equatable, Codable {
    public var command: String
    public var inputPath: String
    public var outputPath: String?
    public var qualificationID: String
    public var toolID: String
    public var status: ToolProcessQualificationStatus
    public var qualified: Bool
    public var scope: ToolQualificationScope
    public var evidenceArtifactIDs: [String]
    public var diagnostics: [String]

    public init(
        command: String = "build-process-evidence",
        inputPath: String,
        outputPath: String?,
        qualificationID: String,
        toolID: String,
        status: ToolProcessQualificationStatus,
        qualified: Bool,
        scope: ToolQualificationScope,
        evidenceArtifactIDs: [String],
        diagnostics: [String]
    ) {
        self.command = command
        self.inputPath = inputPath
        self.outputPath = outputPath
        self.qualificationID = qualificationID
        self.toolID = toolID
        self.status = status
        self.qualified = qualified
        self.scope = scope
        self.evidenceArtifactIDs = evidenceArtifactIDs
        self.diagnostics = diagnostics
    }
}
