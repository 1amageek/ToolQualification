import Foundation

public enum ToolQualificationLevel: String, Sendable, Hashable, Codable, Comparable {
    case unknown
    case smokeChecked
    case corpusChecked
    case oracleChecked
    case productionEligible

    public static func < (lhs: ToolQualificationLevel, rhs: ToolQualificationLevel) -> Bool {
        lhs.rank < rhs.rank
    }

    public var rank: Int {
        switch self {
        case .unknown:
            0
        case .smokeChecked:
            1
        case .corpusChecked:
            2
        case .oracleChecked:
            3
        case .productionEligible:
            4
        }
    }
}
