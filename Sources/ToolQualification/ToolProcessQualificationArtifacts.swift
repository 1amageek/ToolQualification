import CircuiteFoundation

/// Immutable identity artifacts that define one production qualification scope.
public struct ToolProcessQualificationArtifacts: Sendable, Hashable, Codable {
    public var toolExecutable: ArtifactReference
    public var processProfile: ArtifactReference
    public var pdk: ArtifactReference
    public var ruleDeck: ArtifactReference
    public var oracleExecutable: ArtifactReference

    public init(
        toolExecutable: ArtifactReference,
        processProfile: ArtifactReference,
        pdk: ArtifactReference,
        ruleDeck: ArtifactReference,
        oracleExecutable: ArtifactReference
    ) {
        self.toolExecutable = toolExecutable
        self.processProfile = processProfile
        self.pdk = pdk
        self.ruleDeck = ruleDeck
        self.oracleExecutable = oracleExecutable
    }

    public var all: [ArtifactReference] {
        [toolExecutable, processProfile, pdk, ruleDeck, oracleExecutable]
    }
}
