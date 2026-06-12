import Foundation

public struct ToolDescriptor: Sendable, Hashable, Codable {
    public var toolID: String
    public var displayName: String
    public var kind: ToolKind
    public var version: String
    public var capabilities: [ToolCapability]
    public var trustProfile: ToolTrustProfile
    public var environment: ToolEnvironment

    public init(
        toolID: String,
        displayName: String,
        kind: ToolKind,
        version: String,
        capabilities: [ToolCapability],
        trustProfile: ToolTrustProfile,
        environment: ToolEnvironment
    ) {
        self.toolID = toolID
        self.displayName = displayName
        self.kind = kind
        self.version = version
        self.capabilities = capabilities
        self.trustProfile = trustProfile
        self.environment = environment
    }
}
