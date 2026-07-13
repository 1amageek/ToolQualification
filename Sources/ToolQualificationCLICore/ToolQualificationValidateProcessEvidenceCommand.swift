import Foundation
import ToolQualification

/// Implements `toolqualification validate-process-evidence`.
///
/// Exit codes: 0 when the evidence is qualified for the requested scope and
/// evaluation time, 2 when it is readable but not qualified, and 1 for input
/// or argument failures.
public struct ToolQualificationValidateProcessEvidenceCommand: Sendable {
    public struct Options: Sendable, Equatable {
        public var evidencePath: String
        public var requirePDKScope: Bool
        public var evaluatedAt: Date
        public var pretty: Bool

        public init(arguments: [String], now: Date = Date()) throws {
            var evidencePath: String?
            var requirePDKScope = false
            var evaluatedAt = now
            var pretty = false
            var cursor = ToolQualificationCLIArgumentCursor(arguments: arguments)
            while let argument = cursor.next() {
                switch argument {
                case "--evidence":
                    evidencePath = try cursor.requireValue(for: argument)
                case "--require-pdk":
                    requirePDKScope = true
                case "--at":
                    let value = try cursor.requireValue(for: argument)
                    guard let seconds = Double(value), seconds.isFinite else {
                        throw ToolQualificationCLIError.invalidArguments(
                            "--at must be a finite Unix timestamp"
                        )
                    }
                    evaluatedAt = Date(timeIntervalSince1970: seconds)
                case "--pretty":
                    pretty = true
                default:
                    throw ToolQualificationCLIError.invalidArguments(
                        "Unknown argument for validate-process-evidence: \(argument)"
                    )
                }
            }
            guard let evidencePath else {
                throw ToolQualificationCLIError.invalidArguments(
                    "Missing required argument: --evidence"
                )
            }
            self.evidencePath = evidencePath
            self.requirePDKScope = requirePDKScope
            self.evaluatedAt = evaluatedAt
            self.pretty = pretty
        }
    }

    public init() {}

    public func execute(options: Options) throws -> ToolQualificationCLIInvocationResult {
        let evidence = try ToolQualificationCLIJSONCoding.decode(
            ToolProcessQualificationEvidence.self,
            atPath: options.evidencePath
        )
        let structurallyValid = evidence.isStructurallyValid
        let qualified = evidence.isQualified(
            at: options.evaluatedAt,
            requirePDKScope: options.requirePDKScope
        )
        let envelope = ToolQualificationProcessEvidenceEnvelope(
            evidencePath: options.evidencePath,
            qualificationID: evidence.qualificationID,
            toolID: evidence.toolID,
            status: evidence.status,
            structurallyValid: structurallyValid,
            qualified: qualified,
            requirePDKScope: options.requirePDKScope,
            scope: evidence.scope,
            qualifiedAt: iso8601(evidence.qualifiedAt),
            expiresAt: iso8601(evidence.expiresAt),
            evaluatedAt: iso8601(options.evaluatedAt),
            diagnostics: diagnostics(
                for: evidence,
                structurallyValid: structurallyValid,
                qualified: qualified,
                requirePDKScope: options.requirePDKScope,
                evaluatedAt: options.evaluatedAt
            )
        )
        let output = try ToolQualificationCLIJSONCoding.encode(envelope, pretty: options.pretty)
        return ToolQualificationCLIInvocationResult(
            exitCode: qualified ? 0 : 2,
            standardOutput: output + "\n",
            standardError: ""
        )
    }

    private func diagnostics(
        for evidence: ToolProcessQualificationEvidence,
        structurallyValid: Bool,
        qualified: Bool,
        requirePDKScope: Bool,
        evaluatedAt: Date
    ) -> [String] {
        var result: [String] = []
        if !structurallyValid {
            result.append("process-evidence-structurally-invalid")
        }
        if requirePDKScope && !evidence.scope.isCompleteForPDK {
            result.append("process-evidence-pdk-scope-incomplete")
        }
        if evidence.status != .qualified {
            result.append("process-evidence-status-not-qualified")
        }
        if !evidence.independenceVerified {
            result.append("process-evidence-independence-unverified")
        }
        if !evidence.blockers.isEmpty {
            result.append(contentsOf: evidence.blockers.map { "blocker:\($0)" })
        }
        if !evidence.isFresh(at: evaluatedAt) {
            result.append("process-evidence-not-fresh")
        }
        if qualified {
            return []
        }
        return Array(Set(result)).sorted()
    }

    private func iso8601(_ date: Date?) -> String? {
        guard let date else { return nil }
        return iso8601(date)
    }

    private func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
