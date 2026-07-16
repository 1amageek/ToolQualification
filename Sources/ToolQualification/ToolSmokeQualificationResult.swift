import CircuiteFoundation
import Foundation

public struct ToolSmokeQualificationResult: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let resultID: String
    public let qualificationID: String
    public let toolID: String
    public let issuer: ProducerIdentity
    public let inputArtifacts: [ArtifactReference]
    public let outputArtifacts: [ArtifactReference]
    public let diagnostics: [ToolDiagnostic]
    public let checkedAt: Date

    public init(
        resultID: String,
        qualificationID: String,
        toolID: String,
        issuer: ProducerIdentity,
        inputArtifacts: [ArtifactReference],
        outputArtifacts: [ArtifactReference],
        diagnostics: [ToolDiagnostic] = [],
        checkedAt: Date,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.resultID = resultID
        self.qualificationID = qualificationID
        self.toolID = toolID
        self.issuer = issuer
        self.inputArtifacts = inputArtifacts.sorted { $0.id.rawValue < $1.id.rawValue }
        self.outputArtifacts = outputArtifacts.sorted { $0.id.rawValue < $1.id.rawValue }
        self.diagnostics = diagnostics.sorted { $0.code < $1.code }
        self.checkedAt = checkedAt
    }

    public var isStructurallyValid: Bool {
        schemaVersion == Self.currentSchemaVersion
            && !resultID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !qualificationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !toolID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !inputArtifacts.isEmpty
            && !outputArtifacts.isEmpty
    }

    public var isPassing: Bool {
        isStructurallyValid && !diagnostics.contains { $0.severity == .error }
    }

    public func canonicalData() throws -> Data {
        guard isStructurallyValid else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput(
                "smoke result is not structurally valid"
            )
        }
        return try ToolQualificationCanonicalJSON.encode(self)
    }

    public static func decodeCanonical(from data: Data) throws -> Self {
        let result = try ToolQualificationCanonicalJSON.decode(Self.self, from: data)
        guard result.isStructurallyValid else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput(
                "smoke result is not structurally valid"
            )
        }
        return result
    }
}
