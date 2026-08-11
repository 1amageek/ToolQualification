import CircuiteFoundation
import Foundation
import Testing
import ToolQualification
import ToolQualificationCLICore

@Suite("ToolQualification record issuance CLI")
struct ToolQualificationIssueRecordCLITests {
    @Test("issue-record writes a canonical record and workspace reference")
    func writesRecordAndReference() async throws {
        let directory = try makeTemporaryDirectory()
        defer { remove(directory) }
        let request = try makeRequest(healthStatus: .passed)
        let inputURL = directory.appending(path: "issuance-request.json")
        let referenceURL = directory.appending(path: "outputs/record-reference.json")
        try JSONEncoder().encode(request).write(to: inputURL, options: .atomic)
        let artifactFixture = try ToolQualificationCLIArtifactFixture()
        let inventoryURL = try artifactFixture.writeInventory(root: directory, artifacts: [])

        let result = await ToolQualificationCLI.invoke(arguments: [
            "issue-record",
            "--input", inputURL.path,
            "--workspace-root", directory.path,
            "--availability-inventory", inventoryURL.path,
            "--record-path", "qualification/runtime-record.json",
            "--reference-output", referenceURL.path,
            "--pretty",
        ])

        #expect(result.exitCode == 0)
        let recordURL = directory.appending(path: "qualification/runtime-record.json")
        let record = try ToolQualificationRecord.decodeCanonical(from: Data(contentsOf: recordURL))
        let reference = try JSONDecoder().decode(
            ArtifactReference.self,
            from: Data(contentsOf: referenceURL)
        )
        let envelope = try JSONDecoder().decode(
            ToolQualificationIssueRecordEnvelope.self,
            from: Data(result.standardOutput.utf8)
        )
        #expect(record.recordID == request.recordID)
        #expect(record.issuer == request.issuer)
        #expect(envelope.recordReference == reference)
        #expect(envelope.recordAvailability == .local(
            artifactID: reference.id,
            rootID: artifactFixture.rootID,
            relativePath: try ArtifactRelativePath(
                segments: ["qualification", "runtime-record.json"]
            )
        ))
        let validated = try await artifactFixture.withReader(
            root: directory,
            availabilities: [envelope.recordAvailability]
        ) { reader in
            try await ToolQualificationRecordValidator().validatedRecord(
                referencedBy: reference,
                expectedToolID: request.descriptor.toolID,
                reading: reader
            )
        }
        #expect(validated == record)
    }

    @Test("issue-record rejects a failed health result without writing a record")
    func rejectsFailedHealth() async throws {
        let directory = try makeTemporaryDirectory()
        defer { remove(directory) }
        let request = try makeRequest(healthStatus: .failed)
        let inputURL = directory.appending(path: "issuance-request.json")
        try JSONEncoder().encode(request).write(to: inputURL, options: .atomic)
        let inventoryURL = try ToolQualificationCLIArtifactFixture()
            .writeInventory(root: directory, artifacts: [])

        let result = await ToolQualificationCLI.invoke(arguments: [
            "issue-record",
            "--input", inputURL.path,
            "--workspace-root", directory.path,
            "--availability-inventory", inventoryURL.path,
            "--record-path", "qualification/rejected-record.json",
            "--reference-output", directory.appending(path: "rejected-reference.json").path,
        ])

        #expect(result.exitCode == 2)
        #expect(result.standardError.contains("record-issuance-rejected"))
        #expect(!FileManager.default.fileExists(
            atPath: directory.appending(path: "qualification/rejected-record.json").path
        ))
    }

    @Test("issue-record rejects paths outside the workspace")
    func rejectsEscapingRecordPath() async throws {
        let directory = try makeTemporaryDirectory()
        defer { remove(directory) }
        let inputURL = directory.appending(path: "issuance-request.json")
        try JSONEncoder().encode(try makeRequest(healthStatus: .passed))
            .write(to: inputURL, options: .atomic)
        let inventoryURL = try ToolQualificationCLIArtifactFixture()
            .writeInventory(root: directory, artifacts: [])

        let result = await ToolQualificationCLI.invoke(arguments: [
            "issue-record",
            "--input", inputURL.path,
            "--workspace-root", directory.path,
            "--availability-inventory", inventoryURL.path,
            "--record-path", "../escaped-record.json",
            "--reference-output", directory.appending(path: "reference.json").path,
        ])

        #expect(result.exitCode == 1)
        #expect(result.standardError.contains("invalid-arguments"))
    }

    private func makeRequest(
        healthStatus: ToolHealthStatus
    ) throws -> ToolQualificationRecordIssuanceRequest {
        let descriptor = ToolDescriptor(
            toolID: "native-drc",
            displayName: "Native DRC",
            kind: .drc,
            version: "1.0.0",
            capabilities: [ToolCapability(operationID: "drc.run")],
            trustProfile: ToolTrustProfile(level: .unknown),
            environment: ToolEnvironment(platform: "macOS")
        )
        return ToolQualificationRecordIssuanceRequest(
            recordID: "native-drc-runtime-record",
            descriptor: descriptor,
            health: ToolHealthCheckResult(toolID: descriptor.toolID, status: healthStatus),
            issuer: try ProducerIdentity(
                kind: .engine,
                identifier: "tool-qualification",
                version: "1.0.0"
            ),
            issuedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "toolqualification-record-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func remove(_ directory: URL) {
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            Issue.record("Failed to remove fixture: \(error.localizedDescription)")
        }
    }
}
