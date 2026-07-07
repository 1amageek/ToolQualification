import Foundation
import ToolQualification

/// stdout contract for `toolqualification evaluate`.
///
/// Carries the full `ToolTrustDecision` plus the identity of every JSON input
/// the decision was computed from, so an agent can bind the verdict to the
/// exact descriptor/requirement/health artifacts it supplied.
public struct ToolQualificationEvaluateEnvelope: Sendable, Equatable, Codable {
    /// Identity of the JSON inputs used for the evaluation.
    public struct Inputs: Sendable, Equatable, Codable {
        public var descriptorPath: String
        public var descriptorToolID: String
        public var descriptorVersion: String
        public var descriptorKind: ToolKind
        public var descriptorTrustLevel: ToolQualificationLevel
        public var requirementPath: String
        public var requirementKind: ToolKind
        public var requirementOperationID: String
        public var requirementMinimumLevel: ToolQualificationLevel
        public var healthPath: String?
        public var healthToolID: String?
        public var healthStatus: ToolHealthStatus?

        public init(
            descriptorPath: String,
            descriptorToolID: String,
            descriptorVersion: String,
            descriptorKind: ToolKind,
            descriptorTrustLevel: ToolQualificationLevel,
            requirementPath: String,
            requirementKind: ToolKind,
            requirementOperationID: String,
            requirementMinimumLevel: ToolQualificationLevel,
            healthPath: String? = nil,
            healthToolID: String? = nil,
            healthStatus: ToolHealthStatus? = nil
        ) {
            self.descriptorPath = descriptorPath
            self.descriptorToolID = descriptorToolID
            self.descriptorVersion = descriptorVersion
            self.descriptorKind = descriptorKind
            self.descriptorTrustLevel = descriptorTrustLevel
            self.requirementPath = requirementPath
            self.requirementKind = requirementKind
            self.requirementOperationID = requirementOperationID
            self.requirementMinimumLevel = requirementMinimumLevel
            self.healthPath = healthPath
            self.healthToolID = healthToolID
            self.healthStatus = healthStatus
        }
    }

    public var command: String
    public var toolID: String
    public var eligible: Bool
    public var decision: ToolTrustDecision
    public var inputs: Inputs

    public init(
        command: String,
        toolID: String,
        eligible: Bool,
        decision: ToolTrustDecision,
        inputs: Inputs
    ) {
        self.command = command
        self.toolID = toolID
        self.eligible = eligible
        self.decision = decision
        self.inputs = inputs
    }
}
