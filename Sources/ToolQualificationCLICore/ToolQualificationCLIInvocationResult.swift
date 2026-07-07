import Foundation

/// Captured outcome of one CLI invocation: exit code plus the exact bytes the
/// process writes to stdout and stderr. Tests exercise the CLI through this
/// value; the executable entry point replays it onto the real file handles.
public struct ToolQualificationCLIInvocationResult: Sendable, Equatable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String

    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}
