import CircuiteFoundation
import Foundation
import Testing
import ToolQualificationCLICore

@Suite("ToolQualification CLI artifact availability inventory")
struct ToolQualificationCLIArtifactAvailabilityInventoryTests {
    @Test("inventory rejects duplicate artifact identities")
    func rejectsDuplicateArtifacts() throws {
        let fixture = try Fixture()

        #expect(throws: ToolQualificationCLIArtifactAvailabilityInventoryError
            .duplicateArtifact(fixture.artifactID)) {
            _ = try ToolQualificationCLIArtifactAvailabilityInventory(
                rootID: fixture.rootID,
                budget: fixture.budget,
                availabilities: [fixture.availability, fixture.availability]
            )
        }
    }

    @Test("inventory rejects an availability from another root")
    func rejectsRootMismatch() throws {
        let fixture = try Fixture()
        let otherRootID = try ArtifactRootID(rawValue: "other-artifact-root")

        #expect(throws: ToolQualificationCLIArtifactAvailabilityInventoryError
            .rootMismatch(expected: fixture.rootID, actual: otherRootID)) {
            _ = try ToolQualificationCLIArtifactAvailabilityInventory(
                rootID: fixture.rootID,
                budget: fixture.budget,
                availabilities: [.local(
                    artifactID: fixture.artifactID,
                    rootID: otherRootID,
                    relativePath: fixture.relativePath
                )]
            )
        }
    }

    @Test("inventory decoder rejects an unsupported schema version")
    func rejectsUnsupportedSchema() throws {
        let fixture = try Fixture()
        let valid = try ToolQualificationCLIArtifactAvailabilityInventory(
            rootID: fixture.rootID,
            budget: fixture.budget,
            availabilities: [fixture.availability]
        )
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as? [String: Any]
        )
        object["schemaVersion"] = 2

        #expect(throws: ToolQualificationCLIArtifactAvailabilityInventoryError
            .unsupportedSchemaVersion(2)) {
            _ = try JSONDecoder().decode(
                ToolQualificationCLIArtifactAvailabilityInventory.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }
    }
}

private struct Fixture {
    let rootID: ArtifactRootID
    let artifactID: ArtifactID
    let relativePath: ArtifactRelativePath
    let availability: ArtifactAvailability
    let budget: ArtifactAccessBudget

    init() throws {
        rootID = try ArtifactRootID(rawValue: "artifact-root")
        let digest = try ContentDigest(
            algorithm: .sha256,
            hexadecimalValue: String(repeating: "1", count: 64)
        )
        artifactID = try ArtifactID(digest: digest, byteCount: 1)
        relativePath = try ArtifactRelativePath(segments: ["qualification", "evidence.json"])
        availability = .local(
            artifactID: artifactID,
            rootID: rootID,
            relativePath: relativePath
        )
        budget = try ArtifactAccessBudget(
            maximumPageByteCount: 1,
            maximumTotalByteCount: 1,
            maximumPageCount: 1,
            maximumWorkUnitCount: 1,
            maximumDurationNanoseconds: 1
        )
    }
}
