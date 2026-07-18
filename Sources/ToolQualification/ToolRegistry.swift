import Foundation

public struct ToolRegistry: Sendable, Hashable, Codable {
    public private(set) var descriptors: [String: ToolDescriptor]

    private enum CodingKeys: String, CodingKey {
        case descriptors
    }

    public init() {
        descriptors = [:]
    }

    public init(descriptors: [ToolDescriptor]) throws {
        var descriptorsByID: [String: ToolDescriptor] = [:]
        for descriptor in descriptors {
            try Self.validateToolID(descriptor.toolID)
            guard descriptorsByID[descriptor.toolID] == nil else {
                throw ToolQualificationError.duplicateToolID(descriptor.toolID)
            }
            descriptorsByID[descriptor.toolID] = descriptor
        }
        self.descriptors = descriptorsByID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try container.decode([String: ToolDescriptor].self, forKey: .descriptors)
        guard decoded.allSatisfy({ $0.key == $0.value.toolID }) else {
            throw DecodingError.dataCorruptedError(
                forKey: .descriptors,
                in: container,
                debugDescription: "Tool registry keys must match descriptor tool IDs."
            )
        }
        try self.init(descriptors: Array(decoded.values))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(descriptors, forKey: .descriptors)
    }

    public func descriptor(toolID: String) -> ToolDescriptor? {
        descriptors[toolID]
    }

    public mutating func upsert(_ descriptor: ToolDescriptor) throws {
        try Self.validateToolID(descriptor.toolID)
        descriptors[descriptor.toolID] = descriptor
    }

    public func candidates(
        requirement: ToolTrustRequirement,
        healthResults: [String: ToolHealthCheckResult] = [:],
        artifactReader: (any ToolQualificationArtifactReading)? = nil,
        evaluator: any ToolTrustEvaluating = ToolTrustEvaluator()
    ) async -> [(descriptor: ToolDescriptor, decision: ToolTrustDecision)] {
        var evaluated: [(descriptor: ToolDescriptor, decision: ToolTrustDecision)] = []
        for descriptor in descriptors.values {
            evaluated.append((
                descriptor,
                await evaluator.evaluate(
                    descriptor: descriptor,
                    requirement: requirement,
                    health: healthResults[descriptor.toolID],
                    artifactReader: artifactReader
                )
            ))
        }
        return evaluated
            .filter { $0.decision.status == .eligible }
            .sorted { lhs, rhs in
                if lhs.descriptor.trustProfile.level != rhs.descriptor.trustProfile.level {
                    return lhs.descriptor.trustProfile.level > rhs.descriptor.trustProfile.level
                }
                return lhs.descriptor.toolID < rhs.descriptor.toolID
            }
    }

    public func select(
        requirement: ToolTrustRequirement,
        healthResults: [String: ToolHealthCheckResult] = [:],
        artifactReader: (any ToolQualificationArtifactReading)? = nil,
        evaluator: any ToolTrustEvaluating = ToolTrustEvaluator()
    ) async -> ToolDescriptor? {
        await candidates(
            requirement: requirement,
            healthResults: healthResults,
            artifactReader: artifactReader,
            evaluator: evaluator
        ).first?.descriptor
    }

    private static func validateToolID(_ toolID: String) throws {
        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
        )
        guard !toolID.isEmpty,
              toolID.count <= 128,
              toolID != ".",
              toolID != "..",
              toolID.unicodeScalars.allSatisfy(allowed.contains) else {
            throw ToolQualificationError.invalidToolID(toolID)
        }
    }
}
