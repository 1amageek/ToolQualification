import CircuiteFoundation
import Foundation

public protocol ToolQualificationRecordValidating: Sendable {
    func validatedRecord(
        referencedBy artifact: ArtifactReference,
        expectedToolID: String,
        reading artifacts: any ToolQualificationArtifactReading
    ) async throws -> ToolQualificationRecord
}
