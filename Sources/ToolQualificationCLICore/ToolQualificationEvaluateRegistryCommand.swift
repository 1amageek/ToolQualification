import Foundation
import ToolQualification

/// Implements `toolqualification evaluate-registry`: decode an array of
/// `ToolDescriptor` values, one `ToolTrustRequirement`, and an optional
/// `[toolID: ToolHealthCheckResult]` dictionary, evaluate every descriptor,
/// and emit all decisions ranked the way DesignFlowKernel orders stage tools
/// (eligible first, trust level descending, toolID ascending) plus the
/// selected first-eligible toolID.
///
/// Exit codes: 0 when at least one tool is eligible, 2 when none is.
/// Input failures throw `ToolQualificationCLIError` (exit 1).
public struct ToolQualificationEvaluateRegistryCommand: Sendable {
    public struct Options: Sendable, Equatable {
        public var descriptorsPath: String
        public var requirementPath: String
        public var healthResultsPath: String?
        public var pretty: Bool

        public init(arguments: [String]) throws {
            var descriptorsPath: String?
            var requirementPath: String?
            var healthResultsPath: String?
            var pretty = false
            var cursor = ToolQualificationCLIArgumentCursor(arguments: arguments)
            while let argument = cursor.next() {
                switch argument {
                case "--descriptors":
                    descriptorsPath = try cursor.requireValue(for: argument)
                case "--requirement":
                    requirementPath = try cursor.requireValue(for: argument)
                case "--health-results":
                    healthResultsPath = try cursor.requireValue(for: argument)
                case "--pretty":
                    pretty = true
                default:
                    throw ToolQualificationCLIError.invalidArguments(
                        "Unknown argument for evaluate-registry: \(argument)"
                    )
                }
            }
            guard let descriptorsPath else {
                throw ToolQualificationCLIError.invalidArguments(
                    "Missing required argument: --descriptors"
                )
            }
            guard let requirementPath else {
                throw ToolQualificationCLIError.invalidArguments(
                    "Missing required argument: --requirement"
                )
            }
            self.descriptorsPath = descriptorsPath
            self.requirementPath = requirementPath
            self.healthResultsPath = healthResultsPath
            self.pretty = pretty
        }
    }

    public init() {}

    public func execute(options: Options) throws -> ToolQualificationCLIInvocationResult {
        let descriptors = try ToolQualificationCLIJSONCoding.decode(
            [ToolDescriptor].self,
            atPath: options.descriptorsPath
        )
        let requirement = try ToolQualificationCLIJSONCoding.decode(
            ToolTrustRequirement.self,
            atPath: options.requirementPath
        )
        let healthResults: [String: ToolHealthCheckResult]
        if let healthResultsPath = options.healthResultsPath {
            healthResults = try ToolQualificationCLIJSONCoding.decode(
                [String: ToolHealthCheckResult].self,
                atPath: healthResultsPath
            )
        } else {
            healthResults = [:]
        }

        let evaluator = ToolTrustEvaluator()
        let evaluated = descriptors.map { descriptor in
            (
                descriptor: descriptor,
                decision: evaluator.evaluate(
                    descriptor: descriptor,
                    requirement: requirement,
                    health: healthResults[descriptor.toolID]
                )
            )
        }
        // Mirrors DesignFlowKernel DefaultFlowOrchestrator.evaluatedToolDecisions:
        // eligible first, then trust level descending, then toolID ascending.
        let ranked = evaluated.sorted { lhs, rhs in
            if lhs.decision.status != rhs.decision.status {
                return lhs.decision.status == .eligible
            }
            if lhs.descriptor.trustProfile.level != rhs.descriptor.trustProfile.level {
                return lhs.descriptor.trustProfile.level > rhs.descriptor.trustProfile.level
            }
            return lhs.descriptor.toolID < rhs.descriptor.toolID
        }
        let selected = ranked.first { $0.decision.status == .eligible }
        let eligibleCount = ranked.count { $0.decision.status == .eligible }

        let envelope = ToolQualificationRegistryEnvelope(
            command: "evaluate-registry",
            descriptorsPath: options.descriptorsPath,
            requirementPath: options.requirementPath,
            healthResultsPath: options.healthResultsPath,
            requirement: ToolQualificationRegistryEnvelope.RequirementIdentity(
                kind: requirement.kind,
                operationID: requirement.operationID,
                minimumLevel: requirement.minimumLevel
            ),
            evaluatedCount: ranked.count,
            eligibleCount: eligibleCount,
            selectedToolID: selected?.descriptor.toolID,
            decisions: ranked.map { entry in
                ToolQualificationRegistryEnvelope.RankedDecision(
                    toolID: entry.descriptor.toolID,
                    toolVersion: entry.descriptor.version,
                    trustLevel: entry.descriptor.trustProfile.level,
                    eligible: entry.decision.status == .eligible,
                    decision: entry.decision
                )
            }
        )
        let output = try ToolQualificationCLIJSONCoding.encode(envelope, pretty: options.pretty)
        return ToolQualificationCLIInvocationResult(
            exitCode: selected != nil ? 0 : 2,
            standardOutput: output + "\n",
            standardError: ""
        )
    }
}
