import Foundation
import CircuiteFoundation

public struct ToolCapability: Sendable, Hashable, Codable {
    public var operationID: String
    public var inputFormats: [ArtifactFormat]
    public var outputFormats: [ArtifactFormat]
    public var limitations: [String]

    public init(
        operationID: String,
        inputFormats: [ArtifactFormat] = [],
        outputFormats: [ArtifactFormat] = [],
        limitations: [String] = []
    ) {
        self.operationID = operationID
        self.inputFormats = inputFormats
        self.outputFormats = outputFormats
        self.limitations = limitations
    }
}
