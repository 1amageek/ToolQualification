import CircuiteFoundation
import Foundation

public protocol ToolQualificationArtifactReading: Sendable {
    func verifiedData(for reference: ArtifactReference) async throws -> Data
}
