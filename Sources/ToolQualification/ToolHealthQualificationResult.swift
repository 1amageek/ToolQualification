import Foundation
import CircuiteFoundation

public struct ToolHealthQualificationResult: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let resultID: String
    public let qualificationID: String
    public let toolID: String
    public let scope: ToolQualificationScope
    public let issuer: ProducerIdentity
    public let inputArtifacts: [ArtifactReference]
    public let outputArtifacts: [ArtifactReference]
    public let diagnostics: [ToolDiagnostic]
    public let checkedAt: Date

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case resultID
        case qualificationID
        case toolID
        case scope
        case issuer
        case inputArtifacts
        case outputArtifacts
        case diagnostics
        case checkedAt
    }

    public init(
        resultID: String,
        qualificationID: String,
        toolID: String,
        scope: ToolQualificationScope,
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
        self.scope = scope
        self.issuer = issuer
        self.inputArtifacts = inputArtifacts.sorted { $0.id.rawValue < $1.id.rawValue }
        self.outputArtifacts = outputArtifacts.sorted { $0.id.rawValue < $1.id.rawValue }
        self.diagnostics = diagnostics
        self.checkedAt = checkedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Expected health qualification schema version \(Self.currentSchemaVersion)."
            )
        }
        self.init(
            resultID: try container.decode(String.self, forKey: .resultID),
            qualificationID: try container.decode(String.self, forKey: .qualificationID),
            toolID: try container.decode(String.self, forKey: .toolID),
            scope: try container.decode(ToolQualificationScope.self, forKey: .scope),
            issuer: try container.decode(ProducerIdentity.self, forKey: .issuer),
            inputArtifacts: try container.decode([ArtifactReference].self, forKey: .inputArtifacts),
            outputArtifacts: try container.decode([ArtifactReference].self, forKey: .outputArtifacts),
            diagnostics: try container.decode([ToolDiagnostic].self, forKey: .diagnostics),
            checkedAt: try container.decode(Date.self, forKey: .checkedAt),
            schemaVersion: schemaVersion
        )
    }

    public var isStructurallyValid: Bool {
        schemaVersion == Self.currentSchemaVersion
            && !resultID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !qualificationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !toolID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && scope.isComplete
            && !inputArtifacts.isEmpty
            && !outputArtifacts.isEmpty
            && diagnostics.allSatisfy {
                !$0.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !$0.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
    }

    public var status: ToolHealthStatus {
        diagnostics.contains { $0.severity == .error } ? .failed : .passed
    }

    public var isPassing: Bool {
        isStructurallyValid
            && !diagnostics.contains { $0.severity == .error }
    }

    public func canonicalData() throws -> Data {
        guard isStructurallyValid else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput("health result is not structurally valid")
        }
        let sortedDiagnostics = diagnostics.sorted {
            ($0.severity.rawValue, $0.code, $0.message) < ($1.severity.rawValue, $1.code, $1.message)
        }
        let normalized = ToolHealthQualificationResult(
            resultID: resultID,
            qualificationID: qualificationID,
            toolID: toolID,
            scope: scope,
            issuer: issuer,
            inputArtifacts: inputArtifacts,
            outputArtifacts: outputArtifacts,
            diagnostics: sortedDiagnostics,
            checkedAt: checkedAt,
            schemaVersion: schemaVersion
        )
        return try ToolQualificationCanonicalJSON.encode(normalized)
    }

    public static func decodeCanonical(from data: Data) throws -> Self {
        let result = try ToolQualificationCanonicalJSON.decode(Self.self, from: data)
        guard result.isStructurallyValid, try result.canonicalData() == data else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput("health result is not canonical")
        }
        return result
    }
}
