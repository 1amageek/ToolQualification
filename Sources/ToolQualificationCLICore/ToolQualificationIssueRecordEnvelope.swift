import CircuiteFoundation
import Foundation

public struct ToolQualificationIssueRecordEnvelope: Sendable, Hashable, Codable {
    public let command: String
    public let recordID: String
    public let toolID: String
    public let recordPath: String
    public let referencePath: String
    public let recordReference: ArtifactReference
    public let recordAvailability: ArtifactAvailability

    public init(
        recordID: String,
        toolID: String,
        recordPath: String,
        referencePath: String,
        recordReference: ArtifactReference,
        recordAvailability: ArtifactAvailability
    ) {
        command = "issue-record"
        self.recordID = recordID
        self.toolID = toolID
        self.recordPath = recordPath
        self.referencePath = referencePath
        self.recordReference = recordReference
        self.recordAvailability = recordAvailability
    }
}
