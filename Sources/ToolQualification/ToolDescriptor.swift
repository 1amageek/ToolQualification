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
        return Self.isValidToolID(toolID)
            && Self.isToken(displayName)
            && Self.isToken(version)
            && !capabilities.isEmpty
            && capabilities.allSatisfy(\.isStructurallyValid)
            && Set(operationIDs).count == operationIDs.count
            && trustProfile.isStructurallyValid
            && environment.isStructurallyValid
    }

    private static func isValidToolID(_ value: String) -> Bool {
        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
        )
        return !value.isEmpty
            && value.count <= 128
            && value != "."
            && value != ".."
            && value.unicodeScalars.allSatisfy(allowed.contains)
    }

    private static func isToken(_ value: String) -> Bool {
        !value.isEmpty
            && value.trimmingCharacters(in: .whitespacesAndNewlines) == value
            && !value.unicodeScalars.contains {
                CharacterSet.controlCharacters.contains($0)
            }
    }
}
