import Foundation
import CircuiteFoundation

public struct ToolCapability: Sendable, Hashable, Codable {
    public var operationID: String
    public var inputFormats: [ArtifactFormat]
    public var outputFormats: [ArtifactFormat]
    public var limitations: [String]

    public init(
        operationID: String,
        inputFormats: [ArtifactFormat] = [],
        outputFormats: [ArtifactFormat] = [],
        limitations: [String] = []
    ) {
        self.operationID = operationID
        self.inputFormats = inputFormats
        self.outputFormats = outputFormats
        self.limitations = limitations
    }

    public var isStructurallyValid: Bool {
        !operationID.isEmpty
            && operationID.trimmingCharacters(in: .whitespacesAndNewlines) == operationID
            && !operationID.unicodeScalars.contains {
                CharacterSet.controlCharacters.contains($0)
            }
            && Set(inputFormats).count == inputFormats.count
            && Set(outputFormats).count == outputFormats.count
            && limitations.allSatisfy {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            && Set(limitations).count == limitations.count
    }
}
