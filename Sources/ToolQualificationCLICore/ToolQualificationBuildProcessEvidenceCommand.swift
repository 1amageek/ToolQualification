import Foundation
import ToolQualification

public struct ToolQualificationBuildProcessEvidenceCommand: Sendable {
    public struct Options: Sendable, Equatable {
        public var inputPath: String
        public var outputPath: String
        public var evaluatedAt: Date
        public var pretty: Bool

        public init(arguments: [String], now: Date = Date()) throws {
            var inputPath: String?
            var outputPath: String?
            var evaluatedAt = now
            var pretty = false
            var cursor = ToolQualificationCLIArgumentCursor(arguments: arguments)
            while let argument = cursor.next() {
                switch argument {
                case "--input":
                    inputPath = try cursor.requireValue(for: argument)
                case "--output":
                    outputPath = try cursor.requireValue(for: argument)
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
                        "Unknown argument for build-process-evidence: \(argument)"
                    )
                }
            }
            guard let inputPath else {
                throw ToolQualificationCLIError.invalidArguments(
                    "Missing required argument: --input"
                )
            }
            guard let outputPath else {
                throw ToolQualificationCLIError.invalidArguments(
                    "Missing required argument: --output"
                )
            }
            self.inputPath = inputPath
            self.outputPath = outputPath
            self.evaluatedAt = evaluatedAt
            self.pretty = pretty
        }
    }

    public init() {}

    public func execute(options: Options) throws -> ToolQualificationCLIInvocationResult {
        let request = try ToolQualificationCLIJSONCoding.decode(
            ToolProcessQualificationEvidenceBuildRequest.self,
            atPath: options.inputPath
        )
        do {
            let evidence = try ToolProcessQualificationEvidenceBuilder().build(
                request,
                at: options.evaluatedAt
            )
            let encoded = try ToolQualificationCLIJSONCoding.encode(
                evidence,
                pretty: options.pretty
            )
            do {
                try Data(encoded.utf8).write(
                    to: URL(filePath: options.outputPath),
                    options: .atomic
                )
            } catch {
                throw ToolQualificationCLIError.unwritableFile(
                    path: options.outputPath,
                    reason: error.localizedDescription
                )
            }
            let envelope = ToolQualificationBuildProcessEvidenceEnvelope(
                inputPath: options.inputPath,
                outputPath: options.outputPath,
                qualificationID: evidence.qualificationID,
                toolID: evidence.toolID,
                status: evidence.status,
                qualified: true,
                scope: evidence.scope,
                evidenceArtifactIDs: evidence.evidenceArtifactIDs,
                diagnostics: []
            )
            return ToolQualificationCLIInvocationResult(
                exitCode: 0,
                standardOutput: try ToolQualificationCLIJSONCoding.encode(
                    envelope,
                    pretty: options.pretty
                ) + "\n",
                standardError: ""
            )
        } catch let error as ToolProcessQualificationEvidenceBuildError {
            let envelope = ToolQualificationBuildProcessEvidenceEnvelope(
                inputPath: options.inputPath,
                outputPath: nil,
                qualificationID: request.qualificationID,
                toolID: request.toolID,
                status: .blocked,
                qualified: false,
                scope: request.scope,
                evidenceArtifactIDs: request.evidenceArtifacts.map {
                    $0.artifactID ?? $0.path
                }.sorted(),
                diagnostics: [error.localizedDescription]
            )
            return ToolQualificationCLIInvocationResult(
                exitCode: 2,
                standardOutput: try ToolQualificationCLIJSONCoding.encode(
                    envelope,
                    pretty: options.pretty
                ) + "\n",
                standardError: ""
            )
        }
    }
}
