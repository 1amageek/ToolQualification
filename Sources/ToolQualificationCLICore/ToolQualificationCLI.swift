import Foundation
import ToolQualification

/// Headless CLI over the ToolQualification trust gate.
///
/// Exposes the same evaluation semantics DesignFlowKernel applies per flow
/// stage (`ToolTrustEvaluator().evaluate(descriptor:requirement:health:)`) so
/// an agent can preflight tool trust decisions from a shell.
///
/// Exit codes: 0 eligible (or at least one eligible tool), 2 evaluated but not
/// eligible (or no eligible tool), 1 argument/IO/decode failure with a JSON
/// diagnostic envelope on stderr.
public enum ToolQualificationCLI {
    /// Runs the CLI against the real stdout/stderr file handles.
    public static func run(arguments: [String]) -> Int32 {
        let result = invoke(arguments: arguments)
        if !result.standardOutput.isEmpty {
            FileHandle.standardOutput.write(Data(result.standardOutput.utf8))
        }
        if !result.standardError.isEmpty {
            FileHandle.standardError.write(Data(result.standardError.utf8))
        }
        return result.exitCode
    }

    /// Runs the CLI and captures all output. Used directly by tests.
    public static func invoke(arguments: [String]) -> ToolQualificationCLIInvocationResult {
        do {
            return try dispatch(arguments: arguments)
        } catch let error as ToolQualificationCLIError {
            return failureResult(error)
        } catch {
            return failureResult(.internalError(String(describing: error)))
        }
    }

    private static func dispatch(arguments: [String]) throws -> ToolQualificationCLIInvocationResult {
        guard let command = arguments.first else {
            throw ToolQualificationCLIError.invalidArguments(
                "Missing command. Run 'toolqualification --help' for usage."
            )
        }
        let commandArguments = Array(arguments.dropFirst())
        switch command {
        case "--help", "-h", "help":
            return helpResult(generalHelp)
        case "evaluate":
            if commandArguments.contains("--help") {
                return helpResult(evaluateHelp)
            }
            let options = try ToolQualificationEvaluateCommand.Options(arguments: commandArguments)
            return try ToolQualificationEvaluateCommand().execute(options: options)
        case "evaluate-registry":
            if commandArguments.contains("--help") {
                return helpResult(evaluateRegistryHelp)
            }
            let options = try ToolQualificationEvaluateRegistryCommand.Options(
                arguments: commandArguments
            )
            return try ToolQualificationEvaluateRegistryCommand().execute(options: options)
        case "validate-process-evidence":
            if commandArguments.contains("--help") {
                return helpResult(validateProcessEvidenceHelp)
            }
            let options = try ToolQualificationValidateProcessEvidenceCommand.Options(
                arguments: commandArguments
            )
            return try ToolQualificationValidateProcessEvidenceCommand().execute(options: options)
        default:
            throw ToolQualificationCLIError.invalidArguments(
                "Unknown command: \(command). Run 'toolqualification --help' for usage."
            )
        }
    }

    private static func helpResult(_ text: String) -> ToolQualificationCLIInvocationResult {
        ToolQualificationCLIInvocationResult(
            exitCode: 0,
            standardOutput: text + "\n",
            standardError: ""
        )
    }

    private static func failureResult(
        _ error: ToolQualificationCLIError
    ) -> ToolQualificationCLIInvocationResult {
        let envelope = ToolQualificationCLIDiagnosticEnvelope(
            code: error.code,
            message: error.message
        )
        return ToolQualificationCLIInvocationResult(
            exitCode: 1,
            standardOutput: "",
            standardError: envelope.serialized() + "\n"
        )
    }

    static let generalHelp = """
    OVERVIEW: Headless tool trust-gate evaluation (ToolQualification).

    Replicates the per-stage trust decision DesignFlowKernel makes:
    ToolTrustEvaluator().evaluate(descriptor:requirement:health:).

    USAGE:
      toolqualification evaluate --descriptor <path.json> --requirement <path.json> [--health <path.json>] [--pretty]
      toolqualification evaluate-registry --descriptors <path.json> --requirement <path.json> [--health-results <path.json>] [--pretty]
      toolqualification validate-process-evidence --evidence <path.json> [--require-pdk] [--at <unix-seconds>] [--pretty]
      toolqualification <command> --help

    COMMANDS:
      evaluate           Evaluate one ToolDescriptor against a ToolTrustRequirement.
      evaluate-registry  Evaluate every ToolDescriptor in a JSON array, rank the
                         decisions (eligible first, trust level descending, toolID
                         ascending) and report the selected first-eligible tool.
      validate-process-evidence  Validate a persisted process qualification record
                         at a specific evaluation time and optional PDK scope.

    EXIT CODES:
      0  eligible (evaluate) / at least one eligible tool (evaluate-registry)
      2  evaluated but not eligible / no eligible tool
      1  invalid arguments, unreadable file, or invalid JSON
         (single JSON diagnostic envelope {"code","message"} on stderr)
    """

    static let evaluateHelp = """
    OVERVIEW: Evaluate one ToolDescriptor against a ToolTrustRequirement.

    USAGE:
      toolqualification evaluate --descriptor <path.json> --requirement <path.json> [--health <path.json>] [--pretty]

    OPTIONS:
      --descriptor <path.json>   ToolDescriptor JSON file (required)
      --requirement <path.json>  ToolTrustRequirement JSON file (required)
      --health <path.json>       ToolHealthCheckResult JSON file (optional)
      --pretty                   Pretty-print the stdout JSON envelope

    OUTPUT (stdout, JSON):
      { command, toolID, eligible, decision: ToolTrustDecision, inputs }

    EXIT CODES:
      0  eligible
      2  evaluated but not eligible
      1  invalid arguments, unreadable file, or invalid JSON
    """

    static let evaluateRegistryHelp = """
    OVERVIEW: Evaluate every ToolDescriptor in a JSON array against one
    ToolTrustRequirement and rank the decisions the way DesignFlowKernel
    orders stage tools.

    USAGE:
      toolqualification evaluate-registry --descriptors <path.json> --requirement <path.json> [--health-results <path.json>] [--pretty]

    OPTIONS:
      --descriptors <path.json>     JSON array of ToolDescriptor (required)
      --requirement <path.json>     ToolTrustRequirement JSON file (required)
      --health-results <path.json>  JSON dictionary toolID -> ToolHealthCheckResult (optional)
      --pretty                      Pretty-print the stdout JSON envelope

    OUTPUT (stdout, JSON):
      { command, requirement, evaluatedCount, eligibleCount, selectedToolID,
        decisions: [ { toolID, toolVersion, trustLevel, eligible, decision } ] }
      Decisions are sorted: eligible first, trust level descending, toolID ascending.
      selectedToolID is the first eligible tool, if any.

    EXIT CODES:
      0  at least one eligible tool
      2  no eligible tool
      1  invalid arguments, unreadable file, or invalid JSON
    """

    static let validateProcessEvidenceHelp = """
    OVERVIEW: Validate a persisted ToolProcessQualificationEvidence record.

    USAGE:
      toolqualification validate-process-evidence --evidence <path.json> [--require-pdk] [--at <unix-seconds>] [--pretty]

    OPTIONS:
      --evidence <path.json>  Process qualification evidence JSON (required)
      --require-pdk           Require a complete PDK ID and PDK digest in scope
      --at <unix-seconds>     Evaluate freshness at this Unix timestamp; defaults to now
      --pretty                Pretty-print the stdout JSON envelope

    EXIT CODES:
      0  evidence is qualified and fresh for the requested scope
      2  evidence is readable but not qualified
      1  invalid arguments, unreadable file, or invalid JSON
    """
}
