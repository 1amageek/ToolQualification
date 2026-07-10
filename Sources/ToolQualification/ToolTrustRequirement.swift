import Foundation
import XcircuitePackage

public struct ToolTrustRequirement: Sendable, Hashable, Codable {
    public var kind: ToolKind
    public var operationID: String
    public var minimumLevel: ToolQualificationLevel
    public var requiredInputFormats: [XcircuiteFileFormat]
    public var requiredOutputFormats: [XcircuiteFileFormat]
    public var requiredEvidenceKinds: [ToolEvidenceKind]
    public var requiredQualifiedEvidenceKinds: [ToolEvidenceKind]
    public var maximumEvidenceAgeSeconds: TimeInterval?
    public var requirePassingHealthCheck: Bool

    public init(
        kind: ToolKind,
        operationID: String,
        minimumLevel: ToolQualificationLevel,
        requiredInputFormats: [XcircuiteFileFormat] = [],
        requiredOutputFormats: [XcircuiteFileFormat] = [],
        requiredEvidenceKinds: [ToolEvidenceKind] = [],
        requiredQualifiedEvidenceKinds: [ToolEvidenceKind] = [],
        maximumEvidenceAgeSeconds: TimeInterval? = nil,
        requirePassingHealthCheck: Bool = true
    ) {
        self.kind = kind
        self.operationID = operationID
        self.minimumLevel = minimumLevel
        self.requiredInputFormats = requiredInputFormats
        self.requiredOutputFormats = requiredOutputFormats
        self.requiredEvidenceKinds = requiredEvidenceKinds
        self.requiredQualifiedEvidenceKinds = requiredQualifiedEvidenceKinds
        self.maximumEvidenceAgeSeconds = maximumEvidenceAgeSeconds
        self.requirePassingHealthCheck = requirePassingHealthCheck
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case operationID
        case minimumLevel
        case requiredInputFormats
        case requiredOutputFormats
        case requiredEvidenceKinds
        case requiredQualifiedEvidenceKinds
        case maximumEvidenceAgeSeconds
        case requirePassingHealthCheck
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try container.decode(ToolKind.self, forKey: .kind)
        self.operationID = try container.decode(String.self, forKey: .operationID)
        self.minimumLevel = try container.decode(ToolQualificationLevel.self, forKey: .minimumLevel)
        self.requiredInputFormats = try container.decode(
            [XcircuiteFileFormat].self,
            forKey: .requiredInputFormats
        )
        self.requiredOutputFormats = try container.decode(
            [XcircuiteFileFormat].self,
            forKey: .requiredOutputFormats
        )
        self.requiredEvidenceKinds = try container.decode(
            [ToolEvidenceKind].self,
            forKey: .requiredEvidenceKinds
        )
        self.requiredQualifiedEvidenceKinds = try container.decode(
            [ToolEvidenceKind].self,
            forKey: .requiredQualifiedEvidenceKinds
        )
        self.maximumEvidenceAgeSeconds = try container.decodeIfPresent(
            TimeInterval.self,
            forKey: .maximumEvidenceAgeSeconds
        )
        self.requirePassingHealthCheck = try container.decode(
            Bool.self,
            forKey: .requirePassingHealthCheck
        )
    }
}
