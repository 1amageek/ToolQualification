import Foundation

public struct ToolQualificationCoverage: Sendable, Hashable, Codable {
    public let operatingCornerIDs: [String]

    public init(operatingCornerIDs: [String] = []) {
        self.operatingCornerIDs = Self.normalized(operatingCornerIDs)
    }

    public func covers(operatingCornerIDs required: some Sequence<String>) -> Bool {
        Set(required).isSubset(of: Set(operatingCornerIDs))
    }

    public var isStructurallyValid: Bool {
        operatingCornerIDs.allSatisfy(Self.isToken)
            && Set(operatingCornerIDs).count == operatingCornerIDs.count
    }

    private static func normalized(_ values: [String]) -> [String] {
        Array(Set(values)).sorted()
    }

    private static func isToken(_ value: String) -> Bool {
        !value.isEmpty
            && value.trimmingCharacters(in: .whitespacesAndNewlines) == value
            && !value.unicodeScalars.contains {
                CharacterSet.controlCharacters.contains($0)
            }
    }
}
