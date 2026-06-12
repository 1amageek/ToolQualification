import Foundation
import XcircuitePackage

public struct ToolEvidence: Sendable, Hashable, Codable {
    public var evidenceID: String
    public var kind: ToolEvidenceKind
    public var artifact: XcircuiteFileReference?
    public var checkedAt: Date?

    public init(
        evidenceID: String,
        kind: ToolEvidenceKind,
        artifact: XcircuiteFileReference? = nil,
        checkedAt: Date? = nil
    ) {
        self.evidenceID = evidenceID
        self.kind = kind
        self.artifact = artifact
        self.checkedAt = checkedAt
    }
}
