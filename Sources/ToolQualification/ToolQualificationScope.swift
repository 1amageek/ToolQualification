import Foundation

public struct ToolQualificationScope: Sendable, Hashable, Codable {
    public var implementationID: String
    public var binaryDigest: String
    public var algorithmVersion: String
    public var processProfileID: String
    public var deckDigest: String
    public var pdkID: String?
    public var pdkDigest: String?

    public init(
        implementationID: String,
        binaryDigest: String,
        algorithmVersion: String,
        processProfileID: String,
        deckDigest: String,
        pdkID: String? = nil,
        pdkDigest: String? = nil
    ) {
        self.implementationID = implementationID
        self.binaryDigest = binaryDigest
        self.algorithmVersion = algorithmVersion
        self.processProfileID = processProfileID
        self.deckDigest = deckDigest
        self.pdkID = pdkID
        self.pdkDigest = pdkDigest
    }

    public var isComplete: Bool {
        [
            implementationID,
            binaryDigest,
            algorithmVersion,
            processProfileID,
            deckDigest,
        ].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    public var isCompleteForPDK: Bool {
        guard isComplete else {
            return false
        }
        guard let pdkID, let pdkDigest else {
            return false
        }
        return !pdkID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !pdkDigest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
