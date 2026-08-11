import CircuiteFoundation
import CircuiteFoundationFileSystem
import CircuiteFoundationFoundation
import Foundation
import ToolQualification

public struct ToolQualificationIssueRecordCommand: Sendable {
    public struct Options: Sendable, Equatable {
        public let inputPath: String
        public let workspaceRoot: String
        public let availabilityInventoryPath: String
        public let recordPath: String
        public let referenceOutputPath: String
        public let pretty: Bool

        public init(arguments: [String]) throws {
            var inputPath: String?
            var workspaceRoot: String?
            var availabilityInventoryPath: String?
            var recordPath: String?
            var referenceOutputPath: String?
            var pretty = false
            var cursor = ToolQualificationCLIArgumentCursor(arguments: arguments)
            while let argument = cursor.next() {
                switch argument {
                case "--input":
                    inputPath = try cursor.requireValue(for: argument)
                case "--workspace-root":
                    workspaceRoot = try cursor.requireValue(for: argument)
                case "--availability-inventory":
                    availabilityInventoryPath = try cursor.requireValue(for: argument)
                case "--record-path":
                    recordPath = try cursor.requireValue(for: argument)
                case "--reference-output":
                    referenceOutputPath = try cursor.requireValue(for: argument)
                case "--pretty":
                    pretty = true
                default:
                    throw ToolQualificationCLIError.invalidArguments(
                        "Unknown argument for issue-record: \(argument)"
                    )
                }
            }
            guard let inputPath else {
                throw ToolQualificationCLIError.invalidArguments("Missing required argument: --input")
            }
            guard let workspaceRoot else {
                throw ToolQualificationCLIError.invalidArguments("Missing required argument: --workspace-root")
            }
            guard let availabilityInventoryPath else {
                throw ToolQualificationCLIError.invalidArguments(
                    "Missing required argument: --availability-inventory"
                )
            }
            guard let recordPath else {
                throw ToolQualificationCLIError.invalidArguments("Missing required argument: --record-path")
            }
            guard let referenceOutputPath else {
                throw ToolQualificationCLIError.invalidArguments("Missing required argument: --reference-output")
            }
            self.inputPath = inputPath
            self.workspaceRoot = workspaceRoot
            self.availabilityInventoryPath = availabilityInventoryPath
            self.recordPath = recordPath
            self.referenceOutputPath = referenceOutputPath
            self.pretty = pretty
        }
    }

    public init() {}

    public func execute(options: Options) async throws -> ToolQualificationCLIInvocationResult {
        let request = try ToolQualificationCLIJSONCoding.decode(
            ToolQualificationRecordIssuanceRequest.self,
            atPath: options.inputPath
        )
        let workspaceRoot = URL(filePath: options.workspaceRoot).standardizedFileURL
        let location: ArtifactLocation
        let relativePath: ArtifactRelativePath
        do {
            location = try ArtifactLocation(workspaceRelativePath: options.recordPath)
            relativePath = try ArtifactRelativePath(
                segments: options.recordPath.split(
                    separator: "/",
                    omittingEmptySubsequences: false
                ).map(String.init)
            )
        } catch {
            throw ToolQualificationCLIError.invalidArguments(
                "--record-path must be a valid workspace-relative path: \(error.localizedDescription)"
            )
        }
        let recordURL: URL
        do {
            recordURL = try location.resolvedFileURL(relativeTo: workspaceRoot)
        } catch {
            throw ToolQualificationCLIError.invalidArguments(
                "--record-path must remain inside --workspace-root: \(error.localizedDescription)"
            )
        }

        let context = try ToolQualificationCLIArtifactContext(
            workspaceRootPath: options.workspaceRoot,
            availabilityInventoryPath: options.availabilityInventoryPath
        )
        let record: ToolQualificationRecord
        do {
            record = try await context.withReader { reader in
                try await DefaultToolQualificationRecordIssuer().issue(
                    recordID: request.recordID,
                    descriptor: request.descriptor,
                    health: request.health,
                    issuer: request.issuer,
                    reading: reader,
                    issuedAt: request.issuedAt
                )
            }
        } catch let error as ToolQualificationRecordError {
            return ToolQualificationCLIInvocationResult(
                exitCode: 2,
                standardOutput: "",
                standardError: ToolQualificationCLIDiagnosticEnvelope(
                    code: "toolqualification.cli.record-issuance-rejected",
                    message: error.localizedDescription
                ).serialized() + "\n"
            )
        }

        do {
            try FileManager.default.createDirectory(
                at: recordURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try record.canonicalData().write(to: recordURL, options: .atomic)
        } catch {
            throw ToolQualificationCLIError.unwritableFile(
                path: recordURL.path,
                reason: error.localizedDescription
            )
        }

        let reference: ArtifactReference
        do {
            reference = try LocalArtifactReferencer().reference(
                ArtifactLocator(
                    location: location,
                    role: .output,
                    kind: .evidence,
                    format: .json
                ),
                relativeTo: workspaceRoot
            )
            let referenceJSON = try ToolQualificationCLIJSONCoding.encode(
                reference,
                pretty: options.pretty
            )
            let referenceOutputURL = URL(filePath: options.referenceOutputPath)
            try FileManager.default.createDirectory(
                at: referenceOutputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(referenceJSON.utf8).write(
                to: referenceOutputURL,
                options: .atomic
            )
        } catch let error as ToolQualificationCLIError {
            throw error
        } catch {
            throw ToolQualificationCLIError.unwritableFile(
                path: options.referenceOutputPath,
                reason: error.localizedDescription
            )
        }

        let availability = ArtifactAvailability.local(
            artifactID: reference.id,
            rootID: context.inventory.rootID,
            relativePath: relativePath
        )

        let envelope = ToolQualificationIssueRecordEnvelope(
            recordID: record.recordID,
            toolID: record.descriptor.toolID,
            recordPath: options.recordPath,
            referencePath: options.referenceOutputPath,
            recordReference: reference,
            recordAvailability: availability
        )
        return ToolQualificationCLIInvocationResult(
            exitCode: 0,
            standardOutput: try ToolQualificationCLIJSONCoding.encode(
                envelope,
                pretty: options.pretty
            ) + "\n",
            standardError: ""
        )
    }
}
