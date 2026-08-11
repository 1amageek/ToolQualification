import CircuiteFoundation

public struct ToolQualificationCLIArtifactAvailabilityInventory:
    Codable,
    Sendable,
    Hashable
{
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let rootID: ArtifactRootID
    public let budget: ArtifactAccessBudget
    public let availabilities: [ArtifactAvailability]

    public init(
        rootID: ArtifactRootID,
        budget: ArtifactAccessBudget,
        availabilities: [ArtifactAvailability],
        schemaVersion: Int = currentSchemaVersion
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ToolQualificationCLIArtifactAvailabilityInventoryError
                .unsupportedSchemaVersion(schemaVersion)
        }
        var artifactIDs = Set<ArtifactID>()
        for availability in availabilities {
            guard artifactIDs.insert(availability.artifactID).inserted else {
                throw ToolQualificationCLIArtifactAvailabilityInventoryError
                    .duplicateArtifact(availability.artifactID)
            }
            switch availability {
            case .local(_, let availabilityRootID, _):
                guard availabilityRootID == rootID else {
                    throw ToolQualificationCLIArtifactAvailabilityInventoryError
                        .rootMismatch(
                            expected: rootID,
                            actual: availabilityRootID
                        )
                }
            case .service(let artifactID, _):
                throw ToolQualificationCLIArtifactAvailabilityInventoryError
                    .unsupportedServiceAvailability(artifactID)
            }
        }
        self.schemaVersion = schemaVersion
        self.rootID = rootID
        self.budget = budget
        self.availabilities = availabilities.sorted {
            $0.artifactID.description < $1.artifactID.description
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            rootID: container.decode(ArtifactRootID.self, forKey: .rootID),
            budget: container.decode(ArtifactAccessBudget.self, forKey: .budget),
            availabilities: container.decode(
                [ArtifactAvailability].self,
                forKey: .availabilities
            ),
            schemaVersion: container.decode(Int.self, forKey: .schemaVersion)
        )
    }
}
