import Foundation
import XcircuitePackage

public struct ToolTrustRequirement: Sendable, Hashable, Codable {
    public var kind: ToolKind
    public var operationID: String
    public var minimumLevel: ToolQualificationLevel
    public var requiredInputFormats: [XcircuiteFileFormat]
    public var requiredOutputFormats: [XcircuiteFileFormat]
    public var requirePassingHealthCheck: Bool

    public init(
        kind: ToolKind,
        operationID: String,
        minimumLevel: ToolQualificationLevel,
        requiredInputFormats: [XcircuiteFileFormat] = [],
        requiredOutputFormats: [XcircuiteFileFormat] = [],
        requirePassingHealthCheck: Bool = true
    ) {
        self.kind = kind
        self.operationID = operationID
        self.minimumLevel = minimumLevel
        self.requiredInputFormats = requiredInputFormats
        self.requiredOutputFormats = requiredOutputFormats
        self.requirePassingHealthCheck = requirePassingHealthCheck
    }
}
