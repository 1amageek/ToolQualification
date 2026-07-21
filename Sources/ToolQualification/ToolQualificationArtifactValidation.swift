import CircuiteFoundation

enum ToolQualificationArtifactValidation {
    static func isVerifiable(_ artifact: ArtifactReference) -> Bool {
        artifact.locator.location.storage == .workspaceRelative
            && !artifact.locator.location.value.isEmpty
            && artifact.digest.algorithm == .sha256
            && artifact.digest.hexadecimalValue.utf8.count == 64
            && artifact.byteCount > 0
    }

    static func hasDistinctIdentities(_ artifacts: [ArtifactReference]) -> Bool {
        Set(artifacts.map(identityKey)).count == artifacts.count
            && Set(artifacts.map { $0.id.rawValue }).count == artifacts.count
    }

    static func areDisjoint(
        _ lhs: [ArtifactReference],
        _ rhs: [ArtifactReference]
    ) -> Bool {
        Set(lhs.map(identityKey)).isDisjoint(with: Set(rhs.map(identityKey)))
            && Set(lhs.map { $0.id.rawValue }).isDisjoint(
                with: Set(rhs.map { $0.id.rawValue })
            )
    }

    static func identityKey(_ artifact: ArtifactReference) -> String {
        [
            artifact.locator.location.storage.rawValue,
            artifact.locator.location.value,
        ].joined(separator: "|")
    }
}
