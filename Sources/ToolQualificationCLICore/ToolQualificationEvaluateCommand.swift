import Foundation
import ToolQualification

/// Implements `toolqualification evaluate`: decode one `ToolDescriptor`, one
/// `ToolTrustRequirement`, and an optional `ToolHealthCheckResult` from JSON
/// files, optionally verify retained evidence relative to a workspace root,
/// run `ToolTrustEvaluator`, and emit the decision envelope on stdout.
///
/// Exit codes: 0 when the tool is eligible, 2 when it evaluated but is not
/// eligible. Input failures throw `ToolQualificationCLIError` (exit 1).
public struct ToolQualificationEvaluateCommand: Sendable {
    public struct Options: Sendable, Equatable {
        public var descriptorPath: String
        public var requirementPath: String
        public var healthPath: String?
        public var workspaceRootPath: String?
        public var pretty: Bool

        public init(arguments: [String]) throws {
            var descriptorPath: String?
            var requirementPath: String?
            var healthPath: String?
            var workspaceRootPath: String?
            var pretty = false
            var cursor = ToolQualificationCLIArgumentCursor(arguments: arguments)
            while let argument = cursor.next() {
                switch argument {
                case "--descriptor":
                    descriptorPath = try cursor.requireValue(for: argument)
                case "--requirement":
                    requirementPath = try cursor.requireValue(for: argument)
                case "--health":
                    healthPath = try cursor.requireValue(for: argument)
                case "--workspace-root":
                    workspaceRootPath = try cursor.requireValue(for: argument)
                case "--pretty":
                    pretty = true
                default:
                    throw ToolQualificationCLIError.invalidArguments(
                        "Unknown argument for evaluate: \(argument)"
                    )
                }
            }
            guard let descriptorPath else {
                throw ToolQualificationCLIError.invalidArguments(
                    "Missing required argument: --descriptor"
                )
            }
            guard let requirementPath else {
                throw ToolQualificationCLIError.invalidArguments(
                    "Missing required argument: --requirement"
                )
            }
            self.descriptorPath = descriptorPath
            self.requirementPath = requirementPath
            self.healthPath = healthPath
            self.workspaceRootPath = workspaceRootPath
            self.pretty = pretty
        }
    }

    public init() {}

    public func execute(options: Options) async throws -> ToolQualificationCLIInvocationResult {
        let descriptor = try ToolQualificationCLIJSONCoding.decode(
            ToolDescriptor.self,
            atPath: options.descriptorPath
        )
        let requirement = try ToolQualificationCLIJSONCoding.decode(
            ToolTrustRequirement.self,
            atPath: options.requirementPath
        )
        let health: ToolHealthCheckResult?
        if let healthPath = options.healthPath {
            health = try ToolQualificationCLIJSONCoding.decode(
                ToolHealthCheckResult.self,
                atPath: healthPath
            )
        } else {
            health = nil
        }

        let artifactReader: (any ToolQualificationArtifactReading)?
        if let workspaceRootPath = options.workspaceRootPath {
            artifactReader = LocalToolQualificationArtifactReader(
                workspaceRoot: URL(filePath: workspaceRootPath)
            )
        } else {
            artifactReader = nil
        }

        let decision = await ToolTrustEvaluator().evaluate(
            descriptor: descriptor,
            requirement: requirement,
            health: health,
            artifactReader: artifactReader
        )
        let envelope = ToolQualificationEvaluateEnvelope(
            command: "evaluate",
            toolID: descriptor.toolID,
            eligible: decision.status == .eligible,
            decision: decision,
            inputs: ToolQualificationEvaluateEnvelope.Inputs(
                descriptorPath: options.descriptorPath,
                descriptorToolID: descriptor.toolID,
                descriptorVersion: descriptor.version,
                descriptorKind: descriptor.kind,
                descriptorTrustLevel: descriptor.trustProfile.level,
                requirementPath: options.requirementPath,
                requirementKind: requirement.kind,
                requirementOperationID: requirement.operationID,
                requirementMinimumLevel: requirement.minimumLevel,
                healthPath: options.healthPath,
                healthToolID: health?.toolID,
                healthStatus: health?.status,
                workspaceRootPath: options.workspaceRootPath
            )
        )
        let output = try ToolQualificationCLIJSONCoding.encode(envelope, pretty: options.pretty)
        return ToolQualificationCLIInvocationResult(
            exitCode: decision.status == .eligible ? 0 : 2,
            standardOutput: output + "\n",
            standardError: ""
        )
    }
}
