import Foundation
import ToolQualification

/// stdout contract for `toolqualification evaluate-registry`.
///
/// Decisions are ranked the way `DesignFlowKernel.DefaultFlowOrchestrator`
/// orders stage tools: eligible first, then trust level descending, then
/// toolID ascending. `selectedToolID` is the first eligible tool, if any.
public struct ToolQualificationRegistryEnvelope: Sendable, Equatable, Codable {
    /// Identity of the requirement all descriptors were evaluated against.
    public struct RequirementIdentity: Sendable, Equatable, Codable {
        public var kind: ToolKind
        public var operationID: String
        public var minimumLevel: ToolQualificationLevel

        public init(kind: ToolKind, operationID: String, minimumLevel: ToolQualificationLevel) {
            self.kind = kind
            self.operationID = operationID
            self.minimumLevel = minimumLevel
        }
    }

    /// One evaluated descriptor with its decision, in ranked order.
    public struct RankedDecision: Sendable, Equatable, Codable {
        public var toolID: String
        public var toolVersion: String
        public var trustLevel: ToolQualificationLevel
        public var eligible: Bool
        public var decision: ToolTrustDecision

        public init(
            toolID: String,
            toolVersion: String,
            trustLevel: ToolQualificationLevel,
            eligible: Bool,
            decision: ToolTrustDecision
        ) {
            self.toolID = toolID
            self.toolVersion = toolVersion
            self.trustLevel = trustLevel
            self.eligible = eligible
            self.decision = decision
        }
    }

    public var command: String
    public var descriptorsPath: String
    public var requirementPath: String
    public var healthResultsPath: String?
    public var requirement: RequirementIdentity
    public var evaluatedCount: Int
    public var eligibleCount: Int
    public var selectedToolID: String?
    public var decisions: [RankedDecision]

    public init(
        command: String,
        descriptorsPath: String,
        requirementPath: String,
        healthResultsPath: String?,
        requirement: RequirementIdentity,
        evaluatedCount: Int,
        eligibleCount: Int,
        selectedToolID: String?,
        decisions: [RankedDecision]
    ) {
        self.command = command
        self.descriptorsPath = descriptorsPath
        self.requirementPath = requirementPath
        self.healthResultsPath = healthResultsPath
        self.requirement = requirement
        self.evaluatedCount = evaluatedCount
        self.eligibleCount = eligibleCount
        self.selectedToolID = selectedToolID
        self.decisions = decisions
    }
}
