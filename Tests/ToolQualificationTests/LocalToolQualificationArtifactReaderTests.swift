import CircuiteFoundation
import CircuiteFoundationCrypto
import CircuiteFoundationFileSystem
import CircuiteFoundationFoundation
import Foundation
import Testing

@testable import ToolQualification

@Suite("Local tool qualification artifact reader")
struct LocalToolQualificationArtifactReaderTests {
    @Test("explicit availability reads and verifies exact content")
    func readsVerifiedContent() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let data = try await fixture.withReader(availabilities: [fixture.availability]) {
            reader in
            try await reader.verifiedData(for: fixture.reference)
        }

        #expect(data == fixture.data)
    }

    @Test("missing availability fails with the exact artifact identity")
    func rejectsMissingAvailability() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        await #expect(throws: ToolProcessQualificationEvidenceBuildError
            .artifactAvailabilityMissing(fixture.reference.id.description)) {
            _ = try await fixture.withReader(availabilities: []) { reader in
                try await reader.verifiedData(for: fixture.reference)
            }
        }
    }

    @Test("content changed after referencing cannot be read as verified")
    func rejectsChangedContent() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data("tampered".utf8).write(to: fixture.fileURL, options: .atomic)

        await #expect(throws: ToolProcessQualificationEvidenceBuildError.self) {
            _ = try await fixture.withReader(availabilities: [fixture.availability]) {
                reader in
                try await reader.verifiedData(for: fixture.reference)
            }
        }
    }
}

private struct Fixture {
    let root: URL
    let fileURL: URL
    let data: Data
    let reference: ArtifactReference
    let availability: ArtifactAvailability
    let rootID: ArtifactRootID
    let budget: ArtifactAccessBudget

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "toolqualification-reader-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appending(path: "qualification"),
            withIntermediateDirectories: true
        )
        fileURL = root.appending(path: "qualification/evidence.json")
        data = Data("verified-content".utf8)
        try data.write(to: fileURL, options: .atomic)
        let relativePath = try ArtifactRelativePath(
            segments: ["qualification", "evidence.json"]
        )
        reference = try LocalArtifactReferencer().reference(
            ArtifactLocator(
                location: try ArtifactLocation(
                    workspaceRelativePath: relativePath.stringValue
                ),
                role: .output,
                kind: .evidence,
                format: .json
            ),
            relativeTo: root
        )
        rootID = try ArtifactRootID(rawValue: "toolqualification-reader-test-root")
        availability = .local(
            artifactID: reference.id,
            rootID: rootID,
            relativePath: relativePath
        )
        budget = try ArtifactAccessBudget(
            maximumPageByteCount: 4,
            maximumTotalByteCount: 1_024,
            maximumPageCount: 256,
            maximumWorkUnitCount: 256,
            maximumDurationNanoseconds: 10_000_000_000
        )
    }

    func withReader<Result>(
        availabilities: [ArtifactAvailability],
        _ operation: (any ToolQualificationArtifactReading) async throws -> Result
    ) async throws -> Result {
        let capability = try ArtifactRootCapability(
            rootID: rootID,
            directoryURL: root,
            digester: SHA256ContentDigester()
        )
        let reader = LocalToolQualificationArtifactReader(
            access: capability,
            availabilities: Dictionary(
                uniqueKeysWithValues: availabilities.map { ($0.artifactID, $0) }
            ),
            budget: budget
        )
        do {
            let result = try await operation(reader)
            let termination = await capability.close()
            try await termination.wait()
            return result
        } catch let primaryError {
            let termination = await capability.close()
            do {
                try await termination.wait()
            } catch {
                Issue.record("Artifact root close failed: \(error)")
            }
            throw primaryError
        }
    }

    func remove() {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove fixture: \(error.localizedDescription)")
        }
    }
}
