import CircuiteFoundation
import CircuiteFoundationFoundation
import Foundation

public struct ToolEnvironment: Sendable, Hashable, Codable {
    public var executablePath: String?
    public var libraryPath: String?
    public var platform: String
    public var requiredAssets: [ToolAsset]
    public var executionProducer: ProducerIdentity?

    public init(
        executablePath: String? = nil,
        libraryPath: String? = nil,
        platform: String,
        requiredAssets: [ToolAsset] = [],
        executionProducer: ProducerIdentity? = nil
    ) {
        self.executablePath = executablePath
        self.libraryPath = libraryPath
        self.platform = platform
        self.requiredAssets = requiredAssets
        self.executionProducer = executionProducer
    }

    public var isStructurallyValid: Bool {
        !platform.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (executablePath.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? true)
            && (libraryPath.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? true)
            && requiredAssets.allSatisfy(\.isStructurallyValid)
            && Set(requiredAssets.map { "\($0.kind.rawValue)|\($0.path)" }).count
                == requiredAssets.count
    }
}
