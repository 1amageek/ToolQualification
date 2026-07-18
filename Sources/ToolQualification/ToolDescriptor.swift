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

    public var isStructurallyValid: Bool {
        let operationIDs = capabilities.map(\.operationID)
        return !toolID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !environment.platform.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !capabilities.isEmpty
            && operationIDs.allSatisfy {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            && Set(operationIDs).count == operationIDs.count
    }
}
