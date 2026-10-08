import Foundation
import CircuiteFoundation

/// A domain executor's receipt for a selected model actually consumed by instances.
public struct ToolQualificationModelExecutionReceipt: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 2
    public let schemaVersion: Int
    public let caseID: String
    public let executionID: String
    public let producer: ProducerIdentity
    public let phaseID: String
    public let modelID: String
    public let sourceArtifact: ArtifactReference
    public let selectedModelIdentifier: String
    /// Actual instance identities and their effective numeric parameters in this phase.
    public let consumedInstances: [String: [String: Double]]
    public let inputArtifacts: [ArtifactReference]
    public let modelVersion: String?
    /// Resolved model-only parameters; instance geometry and conditions live in consumedInstances.
    public let resolvedParameters: [String: Double]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, caseID, executionID, producer, phaseID, modelID, sourceArtifact
        case selectedModelIdentifier, consumedInstances, inputArtifacts, modelVersion, resolvedParameters
    }

    public init(
        caseID: String,
        executionID: String,
        producer: ProducerIdentity,
        phaseID: String,
        modelID: String,
        sourceArtifact: ArtifactReference,
        selectedModelIdentifier: String,
        consumedInstances: [String: [String: Double]],
        inputArtifacts: [ArtifactReference],
        modelVersion: String? = nil,
        resolvedParameters: [String: Double],
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.caseID = caseID
        self.executionID = executionID
        self.producer = producer
        self.phaseID = phaseID
        self.modelID = modelID
        self.sourceArtifact = sourceArtifact
        self.selectedModelIdentifier = selectedModelIdentifier
        self.consumedInstances = consumedInstances
        self.inputArtifacts = inputArtifacts.sorted { $0.id.description < $1.id.description }
        self.modelVersion = modelVersion
        self.resolvedParameters = resolvedParameters
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: container,
                debugDescription: "Expected model receipt schema version \(Self.currentSchemaVersion).")
        }
        self.init(caseID: try container.decode(String.self, forKey: .caseID),
            executionID: try container.decode(String.self, forKey: .executionID),
            producer: try container.decode(ProducerIdentity.self, forKey: .producer),
            phaseID: try container.decode(String.self, forKey: .phaseID),
            modelID: try container.decode(String.self, forKey: .modelID),
            sourceArtifact: try container.decode(ArtifactReference.self, forKey: .sourceArtifact),
            selectedModelIdentifier: try container.decode(String.self, forKey: .selectedModelIdentifier),
            consumedInstances: try container.decode([String: [String: Double]].self, forKey: .consumedInstances),
            inputArtifacts: try container.decode([ArtifactReference].self, forKey: .inputArtifacts),
            modelVersion: try container.decodeIfPresent(String.self, forKey: .modelVersion),
            resolvedParameters: try container.decode([String: Double].self, forKey: .resolvedParameters),
            schemaVersion: version)
    }

    public var isStructurallyValid: Bool {
        schemaVersion == Self.currentSchemaVersion
            && [caseID, executionID, phaseID, modelID, selectedModelIdentifier].allSatisfy(ToolQualificationArtifactValidation.isToken)
            && ToolQualificationArtifactValidation.isExecutionProducerKind(producer.kind)
            && ToolQualificationArtifactValidation.isVerifiable(sourceArtifact)
            && !consumedInstances.isEmpty
            && consumedInstances.keys.allSatisfy(ToolQualificationArtifactValidation.isToken)
            && consumedInstances.values.allSatisfy { parameters in
                parameters.keys.allSatisfy(ToolQualificationArtifactValidation.isToken)
                    && parameters.values.allSatisfy(\.isFinite)
            }
            && !inputArtifacts.isEmpty
            && inputArtifacts.allSatisfy(ToolQualificationArtifactValidation.isVerifiable)
            && ToolQualificationArtifactValidation.hasDistinctIdentities(inputArtifacts)
            && inputArtifacts.contains(sourceArtifact)
            && modelVersion.map(ToolQualificationArtifactValidation.isToken) != false
            && resolvedParameters.keys.allSatisfy(ToolQualificationArtifactValidation.isToken)
            && resolvedParameters.values.allSatisfy(\.isFinite)
    }

    public func canonicalData() throws -> Data {
        guard isStructurallyValid else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput("model execution receipt is not structurally valid")
        }
        let normalized = Self(caseID: caseID, executionID: executionID, producer: producer, phaseID: phaseID,
            modelID: modelID, sourceArtifact: sourceArtifact,
            selectedModelIdentifier: selectedModelIdentifier, consumedInstances: consumedInstances,
            inputArtifacts: inputArtifacts, modelVersion: modelVersion,
            resolvedParameters: resolvedParameters, schemaVersion: schemaVersion)
        return try ToolQualificationCanonicalJSON.encode(normalized)
    }

    public static func decodeCanonical(from data: Data) throws -> Self {
        let result = try ToolQualificationCanonicalJSON.decode(Self.self, from: data)
        guard result.isStructurallyValid, try result.canonicalData() == data else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput("model execution receipt is not canonical")
        }
        return result
    }
}
