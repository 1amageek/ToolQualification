import Foundation
import XcircuitePackage

public struct ToolRegistry: Sendable, Hashable, Codable {
    public private(set) var descriptors: [String: ToolDescriptor]

    public init(descriptors: [ToolDescriptor] = []) {
        var descriptorsByID: [String: ToolDescriptor] = [:]
        for descriptor in descriptors {
            descriptorsByID[descriptor.toolID] = descriptor
        }
        self.descriptors = descriptorsByID
    }

    public init(validating descriptors: [ToolDescriptor]) throws {
        var descriptorsByID: [String: ToolDescriptor] = [:]
        let validator = XcircuiteIdentifierValidator()
        for descriptor in descriptors {
            try validator.validate(descriptor.toolID, kind: .toolID)
            guard descriptorsByID[descriptor.toolID] == nil else {
                throw ToolQualificationError.duplicateToolID(descriptor.toolID)
            }
            descriptorsByID[descriptor.toolID] = descriptor
        }
        self.descriptors = descriptorsByID
    }

    public func descriptor(toolID: String) -> ToolDescriptor? {
        descriptors[toolID]
    }

    public mutating func upsert(_ descriptor: ToolDescriptor) {
        descriptors[descriptor.toolID] = descriptor
    }

    public func candidates(
        requirement: ToolTrustRequirement,
        healthResults: [String: ToolHealthCheckResult] = [:],
        evaluator: ToolTrustEvaluator = ToolTrustEvaluator()
    ) -> [(descriptor: ToolDescriptor, decision: ToolTrustDecision)] {
        descriptors.values
            .map { descriptor in
                (
                    descriptor,
                    evaluator.evaluate(
                        descriptor: descriptor,
                        requirement: requirement,
                        health: healthResults[descriptor.toolID]
                    )
                )
            }
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
        evaluator: ToolTrustEvaluator = ToolTrustEvaluator()
    ) -> ToolDescriptor? {
        candidates(
            requirement: requirement,
            healthResults: healthResults,
            evaluator: evaluator
        ).first?.descriptor
    }
}
