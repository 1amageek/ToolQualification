import CircuiteFoundation
import CircuiteFoundationCrypto
import CircuiteFoundationFileSystem
import Foundation
import ToolQualification

struct ToolQualificationCLIArtifactContext: Sendable {
    let inventory: ToolQualificationCLIArtifactAvailabilityInventory
    let reader: LocalToolQualificationArtifactReader
    private let rootCapability: ArtifactRootCapability

    init(
        workspaceRootPath: String,
        availabilityInventoryPath: String
    ) throws {
        inventory = try ToolQualificationCLIJSONCoding.decode(
            ToolQualificationCLIArtifactAvailabilityInventory.self,
            atPath: availabilityInventoryPath
        )
        let workspaceRoot = URL(filePath: workspaceRootPath).standardizedFileURL
        do {
            rootCapability = try ArtifactRootCapability(
                rootID: inventory.rootID,
                directoryURL: workspaceRoot,
                digester: SHA256ContentDigester()
            )
        } catch {
            throw ToolQualificationCLIError.invalidArguments(
                "--workspace-root cannot be opened as an artifact root capability: \(error)"
            )
        }
        reader = LocalToolQualificationArtifactReader(
            access: rootCapability,
            availabilities: Dictionary(
                uniqueKeysWithValues: inventory.availabilities.map {
                    ($0.artifactID, $0)
                }
            ),
            budget: inventory.budget
        )
    }

    func withReader<Result>(
        _ operation: (any ToolQualificationArtifactReading) async throws -> Result
    ) async throws -> Result {
        do {
            let result = try await operation(reader)
            try await close()
            return result
        } catch let primaryError {
            do {
                try await close()
            } catch let closeError {
                throw ToolQualificationCLIError.internalError(
                    "artifact operation failed: \(primaryError); root close failed: \(closeError)"
                )
            }
            throw primaryError
        }
    }

    private func close() async throws {
        let termination = await rootCapability.close()
        do {
            try await termination.wait()
        } catch {
            throw ToolQualificationCLIError.internalError(
                "artifact root close failed: \(error)"
            )
        }
    }
}
