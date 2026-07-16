import CircuiteFoundation
import Foundation

public actor LocalToolQualificationArtifactReader: ToolQualificationArtifactReading {
    private let workspaceRoot: URL
    private let verifier: any ArtifactVerifying

    public init(
        workspaceRoot: URL,
        verifier: any ArtifactVerifying = LocalArtifactVerifier()
    ) {
        self.workspaceRoot = workspaceRoot.standardizedFileURL
        self.verifier = verifier
    }

    public func verifiedData(for reference: ArtifactReference) async throws -> Data {
        let integrity = verifier.verify(reference, relativeTo: workspaceRoot)
        guard integrity.isVerified else {
            let detail = integrity.issues
                .map { $0.detail ?? $0.code.rawValue }
                .joined(separator: "; ")
            throw ToolProcessQualificationEvidenceBuildError.artifactIntegrityFailed(detail)
        }
        let url: URL
        do {
            url = try reference.locator.location.resolvedFileURL(relativeTo: workspaceRoot)
        } catch {
            throw ToolProcessQualificationEvidenceBuildError.artifactIntegrityFailed(
                error.localizedDescription
            )
        }
        do {
            return try await Task.detached(priority: nil) {
                try Data(contentsOf: url, options: [.mappedIfSafe])
            }.value
        } catch {
            throw ToolProcessQualificationEvidenceBuildError.artifactIntegrityFailed(
                error.localizedDescription
            )
        }
    }
}
