import Foundation
import CircuiteFoundation

/// Original observations emitted by a domain executor after completing one case.
public struct ToolQualificationCaseExecution: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 3
    public let schemaVersion: Int
    public let caseID: String
    public let executionID: String
    public let producer: ProducerIdentity
    public let executableArtifact: ArtifactReference
    public let inputArtifacts: [ArtifactReference]
    /// Completed domain phases, with semantic identity owned by the executor.
    public let phaseIDs: [String]
    /// Actual contributing phases for every observed metric, including aggregates.
    public let metricPhaseIDs: [String: [String]]
    public let metricDefinitionArtifacts: [String: ArtifactReference]
    public let modelReceiptArtifacts: [ArtifactReference]
    public let observedMetrics: [String: Double]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, caseID, executionID, producer, executableArtifact
        case inputArtifacts, phaseIDs, metricPhaseIDs, metricDefinitionArtifacts, modelReceiptArtifacts, observedMetrics
    }

    public init(
        caseID: String,
        executionID: String,
        producer: ProducerIdentity,
        executableArtifact: ArtifactReference,
        inputArtifacts: [ArtifactReference],
        phaseIDs: [String],
        metricPhaseIDs: [String: [String]],
        metricDefinitionArtifacts: [String: ArtifactReference] = [:],
        modelReceiptArtifacts: [ArtifactReference],
        observedMetrics: [String: Double],
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.caseID = caseID
        self.executionID = executionID
        self.producer = producer
        self.executableArtifact = executableArtifact
        self.inputArtifacts = inputArtifacts.sorted { $0.id.description < $1.id.description }
        self.phaseIDs = phaseIDs.sorted()
        self.metricPhaseIDs = metricPhaseIDs.mapValues { $0.sorted() }
        self.metricDefinitionArtifacts = metricDefinitionArtifacts
        self.modelReceiptArtifacts = modelReceiptArtifacts.sorted { $0.id.description < $1.id.description }
        self.observedMetrics = observedMetrics
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: container,
                debugDescription: "Expected original execution schema version \(Self.currentSchemaVersion).")
        }
        self.init(caseID: try container.decode(String.self, forKey: .caseID),
            executionID: try container.decode(String.self, forKey: .executionID),
            producer: try container.decode(ProducerIdentity.self, forKey: .producer),
            executableArtifact: try container.decode(ArtifactReference.self, forKey: .executableArtifact),
            inputArtifacts: try container.decode([ArtifactReference].self, forKey: .inputArtifacts),
            phaseIDs: try container.decode([String].self, forKey: .phaseIDs),
            metricPhaseIDs: try container.decode([String: [String]].self, forKey: .metricPhaseIDs),
            metricDefinitionArtifacts: try container.decode([String: ArtifactReference].self, forKey: .metricDefinitionArtifacts),
            modelReceiptArtifacts: try container.decode([ArtifactReference].self, forKey: .modelReceiptArtifacts),
            observedMetrics: try container.decode([String: Double].self, forKey: .observedMetrics),
            schemaVersion: version)
    }

    public var isStructurallyValid: Bool {
        schemaVersion == Self.currentSchemaVersion
            && ToolQualificationArtifactValidation.isToken(caseID)
            && ToolQualificationArtifactValidation.isToken(executionID)
            && ToolQualificationArtifactValidation.isExecutionProducerKind(producer.kind)
            && ToolQualificationArtifactValidation.isVerifiable(executableArtifact)
            && !inputArtifacts.isEmpty
            && inputArtifacts.allSatisfy(ToolQualificationArtifactValidation.isVerifiable)
            && ToolQualificationArtifactValidation.hasDistinctIdentities(inputArtifacts)
            && !phaseIDs.isEmpty
            && phaseIDs.allSatisfy(ToolQualificationArtifactValidation.isToken)
            && Set(phaseIDs).count == phaseIDs.count
            && Set(metricPhaseIDs.keys) == Set(observedMetrics.keys)
            && Set(metricDefinitionArtifacts.keys) == Set(observedMetrics.keys)
            && metricDefinitionArtifacts.values.allSatisfy(ToolQualificationArtifactValidation.isVerifiable)
            && metricPhaseIDs.values.allSatisfy { phases in
                !phases.isEmpty && Set(phases).count == phases.count
                    && Set(phases).isSubset(of: Set(phaseIDs))
            }
            && modelReceiptArtifacts.allSatisfy(ToolQualificationArtifactValidation.isVerifiable)
            && ToolQualificationArtifactValidation.hasDistinctIdentities(modelReceiptArtifacts)
            && ToolQualificationArtifactValidation.areDisjoint(inputArtifacts, modelReceiptArtifacts)
            && !observedMetrics.isEmpty
            && observedMetrics.keys.allSatisfy(ToolQualificationArtifactValidation.isToken)
            && observedMetrics.values.allSatisfy(\.isFinite)
    }

    public func canonicalData() throws -> Data {
        guard isStructurallyValid else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput("original case execution is not structurally valid")
        }
        let normalized = Self(caseID: caseID, executionID: executionID, producer: producer,
            executableArtifact: executableArtifact, inputArtifacts: inputArtifacts,
            phaseIDs: phaseIDs, metricPhaseIDs: metricPhaseIDs,
            metricDefinitionArtifacts: metricDefinitionArtifacts,
            modelReceiptArtifacts: modelReceiptArtifacts, observedMetrics: observedMetrics,
            schemaVersion: schemaVersion)
        return try ToolQualificationCanonicalJSON.encode(normalized)
    }

    public static func decodeCanonical(from data: Data) throws -> Self {
        let result = try ToolQualificationCanonicalJSON.decode(Self.self, from: data)
        guard result.isStructurallyValid, try result.canonicalData() == data else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput("original case execution is not canonical")
        }
        return result
    }
}
