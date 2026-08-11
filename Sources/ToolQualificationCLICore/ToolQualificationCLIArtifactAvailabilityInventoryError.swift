import CircuiteFoundation

public enum ToolQualificationCLIArtifactAvailabilityInventoryError:
    Error,
    Sendable,
    Equatable
{
    case unsupportedSchemaVersion(Int)
    case duplicateArtifact(ArtifactID)
    case unsupportedServiceAvailability(ArtifactID)
    case rootMismatch(expected: ArtifactRootID, actual: ArtifactRootID)
}
