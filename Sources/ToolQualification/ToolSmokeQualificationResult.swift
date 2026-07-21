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

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case resultID
        case qualificationID
        case toolID
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
        self.diagnostics = diagnostics.sorted {
            ($0.severity.rawValue, $0.code, $0.message)
                < ($1.severity.rawValue, $1.code, $1.message)
        }
        self.checkedAt = checkedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Expected smoke qualification schema version \(Self.currentSchemaVersion)."
            )
        }
        self.init(
            resultID: try container.decode(String.self, forKey: .resultID),
            qualificationID: try container.decode(String.self, forKey: .qualificationID),
            toolID: try container.decode(String.self, forKey: .toolID),
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
            && !inputArtifacts.isEmpty
            && inputArtifacts.allSatisfy(ToolQualificationArtifactValidation.isVerifiable)
            && ToolQualificationArtifactValidation.hasDistinctIdentities(inputArtifacts)
            && !outputArtifacts.isEmpty
            && outputArtifacts.allSatisfy(ToolQualificationArtifactValidation.isVerifiable)
            && ToolQualificationArtifactValidation.hasDistinctIdentities(outputArtifacts)
            && ToolQualificationArtifactValidation.areDisjoint(inputArtifacts, outputArtifacts)
            && diagnostics.allSatisfy {
                !$0.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !$0.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            && Set(diagnostics).count == diagnostics.count
            && checkedAt.timeIntervalSinceReferenceDate.isFinite
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
        guard result.isStructurallyValid, try result.canonicalData() == data else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput(
                "smoke result is not canonical"
            )
        }
        return result
    }
}
