import Foundation

public enum ToolQualificationComparisonRule: Sendable, Hashable, Codable {
    case absolute(maximumError: Double)
    case combined(absoluteFloor: Double, maximumRelativeError: Double)

    public func absoluteTolerance(reference: Double) -> Double? {
        guard reference.isFinite else { return nil }
        let bound: Double
        switch self {
        case .absolute(let maximumError):
            guard maximumError.isFinite, maximumError >= 0 else { return nil }
            bound = maximumError
        case .combined(let absoluteFloor, let maximumRelativeError):
            guard absoluteFloor.isFinite, absoluteFloor >= 0,
                  maximumRelativeError.isFinite, maximumRelativeError >= 0 else { return nil }
            bound = absoluteFloor + maximumRelativeError * abs(reference)
        }
        return bound.isFinite ? bound : nil
    }
}
