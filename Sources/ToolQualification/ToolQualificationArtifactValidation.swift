import CircuiteFoundation

enum ToolQualificationArtifactValidation {
    static func isVerifiable(_ artifact: ArtifactReference) -> Bool {
        artifact.id.digest == artifact.digest
            && artifact.id.byteCount == artifact.byteCount
            && artifact.digest.algorithm == .sha256
            && artifact.digest.hexadecimalValue.utf8.count == 64
            && artifact.byteCount > 0
    }

    static func hasDistinctIdentities(_ artifacts: [ArtifactReference]) -> Bool {
        Set(artifacts.map(identityKey)).count == artifacts.count
    }

    static func areDisjoint(
        _ lhs: [ArtifactReference],
        _ rhs: [ArtifactReference]
    ) -> Bool {
        Set(lhs.map(identityKey)).isDisjoint(with: Set(rhs.map(identityKey)))
    }

    static func identityKey(_ artifact: ArtifactReference) -> String {
        artifact.id.description
    }
}
