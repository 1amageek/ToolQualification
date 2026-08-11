import CircuiteFoundation
import CircuiteFoundationCrypto
import CircuiteFoundationFileSystem
import CircuiteFoundationFoundation
import Foundation
import ToolQualification
import ToolQualificationCLICore

struct ToolQualificationCLIArtifactFixture {
    let rootID: ArtifactRootID
    let budget: ArtifactAccessBudget

    init() throws {
        rootID = try ArtifactRootID(rawValue: "toolqualification-cli-test-root")
        budget = try ArtifactAccessBudget(
            maximumPageByteCount: 1_048_576,
            maximumTotalByteCount: 67_108_864,
            maximumPageCount: 256,
            maximumWorkUnitCount: 1_024,
            maximumDurationNanoseconds: 60_000_000_000
        )
    }

    func writeInventory(
        root: URL,
        artifacts: [(reference: ArtifactReference, relativePath: String)],
        named name: String = "artifact-availability.json"
    ) throws -> URL {
        let inventory = try ToolQualificationCLIArtifactAvailabilityInventory(
            rootID: rootID,
            budget: budget,
            availabilities: try artifacts.map { artifact in
                .local(
                    artifactID: artifact.reference.id,
                    rootID: rootID,
                    relativePath: try ArtifactRelativePath(
                        segments: artifact.relativePath.split(
                            separator: "/",
                            omittingEmptySubsequences: false
                        ).map(String.init)
                    )
                )
            }
        )
        let outputURL = root.appending(path: name)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(inventory).write(to: outputURL, options: .atomic)
        return outputURL
    }

    func writeQualificationDirectoryInventory(
        root: URL,
        named name: String = "artifact-availability.json"
    ) throws -> URL {
        let qualificationRoot = root.appending(path: "qualification")
        let keys = try FileManager.default.contentsOfDirectory(
            at: qualificationRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).sorted { $0.path < $1.path }
        let artifacts = try keys.compactMap {
            url -> (reference: ArtifactReference, relativePath: String)? in
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                return nil
            }
            let relativePath = "qualification/\(url.lastPathComponent)"
            let reference = try LocalArtifactReferencer().reference(
                ArtifactLocator(
                    location: try ArtifactLocation(workspaceRelativePath: relativePath),
                    role: .output,
                    kind: .evidence,
                    format: .json
                ),
                relativeTo: root
            )
            return (reference, relativePath)
        }
        return try writeInventory(root: root, artifacts: artifacts, named: name)
    }

    func withReader<Result>(
        root: URL,
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
                throw ToolQualificationCLIError.internalError(
                    "test artifact operation failed: \(primaryError); close failed: \(error)"
                )
            }
            throw primaryError
        }
    }
}
