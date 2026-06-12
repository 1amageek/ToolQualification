import Foundation
import XcircuitePackage

public struct ToolCapability: Sendable, Hashable, Codable {
    public var operationID: String
    public var inputFormats: [XcircuiteFileFormat]
    public var outputFormats: [XcircuiteFileFormat]
    public var limitations: [String]

    public init(
        operationID: String,
        inputFormats: [XcircuiteFileFormat] = [],
        outputFormats: [XcircuiteFileFormat] = [],
        limitations: [String] = []
    ) {
        self.operationID = operationID
        self.inputFormats = inputFormats
        self.outputFormats = outputFormats
        self.limitations = limitations
    }
}
