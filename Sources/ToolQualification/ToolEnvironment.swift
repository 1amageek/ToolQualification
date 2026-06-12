import Foundation

public struct ToolEnvironment: Sendable, Hashable, Codable {
    public var executablePath: String?
    public var libraryPath: String?
    public var platform: String
    public var requiredAssets: [ToolAsset]

    public init(
        executablePath: String? = nil,
        libraryPath: String? = nil,
        platform: String,
        requiredAssets: [ToolAsset] = []
    ) {
        self.executablePath = executablePath
        self.libraryPath = libraryPath
        self.platform = platform
        self.requiredAssets = requiredAssets
    }
}
