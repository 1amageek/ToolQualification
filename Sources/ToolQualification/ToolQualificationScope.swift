import Foundation

public struct ToolQualificationScope: Sendable, Hashable, Codable {
    public var implementationID: String
    public var toolVersion: String
    public var binaryDigest: String
    public var algorithmVersion: String
    public var processProfileID: String
    public var processProfileDigest: String
    public var deckDigest: String
    public var pdkID: String?
    public var pdkDigest: String?
    public var oracle: ToolOracleQualificationScope?

    public init(
        implementationID: String,
        toolVersion: String = "",
        binaryDigest: String,
        algorithmVersion: String,
        processProfileID: String,
        processProfileDigest: String,
        deckDigest: String,
        pdkID: String? = nil,
        pdkDigest: String? = nil,
        oracle: ToolOracleQualificationScope? = nil
    ) {
        self.implementationID = implementationID
        self.toolVersion = toolVersion
        self.binaryDigest = binaryDigest.lowercased()
        self.algorithmVersion = algorithmVersion
        self.processProfileID = processProfileID
        self.processProfileDigest = processProfileDigest.lowercased()
        self.deckDigest = deckDigest.lowercased()
        self.pdkID = pdkID
        self.pdkDigest = pdkDigest?.lowercased()
        self.oracle = oracle
    }

    public var isComplete: Bool {
        [
            implementationID,
            toolVersion,
            algorithmVersion,
            processProfileID,
        ].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            && Self.isSHA256(binaryDigest)
            && Self.isSHA256(processProfileDigest)
            && Self.isSHA256(deckDigest)
    }

    public var isCompleteForPDK: Bool {
        guard isComplete else {
            return false
        }
        guard let pdkID, let pdkDigest else {
            return false
        }
        return !pdkID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && Self.isSHA256(pdkDigest)
    }

    public var isCompleteForProduction: Bool {
        guard isCompleteForPDK, let oracle, oracle.isComplete else {
            return false
        }
        return oracle.implementationID != implementationID
            && oracle.binaryDigest.caseInsensitiveCompare(binaryDigest) != .orderedSame
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57)
                || (byte >= 65 && byte <= 70)
                || (byte >= 97 && byte <= 102)
        }
    }
}
