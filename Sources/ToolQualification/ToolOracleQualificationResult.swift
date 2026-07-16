import Foundation
import CircuiteFoundation

public struct ToolOracleQualificationResult: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let resultID: String
    public let qualificationID: String
    public let primaryToolID: String
    public let oracleToolID: String
    public let scope: ToolQualificationScope
    public let issuer: ProducerIdentity
    public let inputArtifacts: [ArtifactReference]
    public let primaryOutputArtifacts: [ArtifactReference]
    public let oracleOutputArtifacts: [ArtifactReference]
    public let cases: [ToolOracleCaseComparison]
    public let checkedAt: Date

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case resultID
        case qualificationID
        case primaryToolID
        case oracleToolID
        case scope
        case issuer
        case inputArtifacts
        case primaryOutputArtifacts
        case oracleOutputArtifacts
        case cases
        case checkedAt
    }

    public init(
        resultID: String,
        qualificationID: String,
        primaryToolID: String,
        oracleToolID: String,
        scope: ToolQualificationScope,
        issuer: ProducerIdentity,
        inputArtifacts: [ArtifactReference],
        primaryOutputArtifacts: [ArtifactReference],
        oracleOutputArtifacts: [ArtifactReference],
        cases: [ToolOracleCaseComparison],
        checkedAt: Date,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.resultID = resultID
        self.qualificationID = qualificationID
        self.primaryToolID = primaryToolID
        self.oracleToolID = oracleToolID
        self.scope = scope
        self.issuer = issuer
        self.inputArtifacts = inputArtifacts.sorted { $0.id.rawValue < $1.id.rawValue }
        self.primaryOutputArtifacts = primaryOutputArtifacts.sorted { $0.id.rawValue < $1.id.rawValue }
        self.oracleOutputArtifacts = oracleOutputArtifacts.sorted { $0.id.rawValue < $1.id.rawValue }
        self.cases = cases.sorted { $0.caseID < $1.caseID }
        self.checkedAt = checkedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Expected oracle qualification schema version \(Self.currentSchemaVersion)."
            )
        }
        self.init(
            resultID: try container.decode(String.self, forKey: .resultID),
            qualificationID: try container.decode(String.self, forKey: .qualificationID),
            primaryToolID: try container.decode(String.self, forKey: .primaryToolID),
            oracleToolID: try container.decode(String.self, forKey: .oracleToolID),
            scope: try container.decode(ToolQualificationScope.self, forKey: .scope),
            issuer: try container.decode(ProducerIdentity.self, forKey: .issuer),
            inputArtifacts: try container.decode([ArtifactReference].self, forKey: .inputArtifacts),
            primaryOutputArtifacts: try container.decode([ArtifactReference].self, forKey: .primaryOutputArtifacts),
            oracleOutputArtifacts: try container.decode([ArtifactReference].self, forKey: .oracleOutputArtifacts),
            cases: try container.decode([ToolOracleCaseComparison].self, forKey: .cases),
            checkedAt: try container.decode(Date.self, forKey: .checkedAt),
            schemaVersion: schemaVersion
        )
    }

    public var isStructurallyValid: Bool {
        schemaVersion == Self.currentSchemaVersion
            && !resultID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !qualificationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && scope.isCompleteForProduction
            && primaryToolID == scope.implementationID
            && oracleToolID == scope.oracle?.implementationID
            && primaryToolID != oracleToolID
            && !inputArtifacts.isEmpty
            && !primaryOutputArtifacts.isEmpty
            && !oracleOutputArtifacts.isEmpty
            && !cases.isEmpty
            && Set(cases.map(\.caseID)).count == cases.count
            && cases.allSatisfy(\.isStructurallyValid)
    }

    public var isPassing: Bool {
        isStructurallyValid && cases.allSatisfy {
            $0.primaryPassed && $0.oraclePassed && $0.agreed && $0.failureCodes.isEmpty
        }
    }

    public func canonicalData() throws -> Data {
        guard isStructurallyValid else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput("oracle result is not structurally valid")
        }
        let normalized = ToolOracleQualificationResult(
            resultID: resultID,
            qualificationID: qualificationID,
            primaryToolID: primaryToolID,
            oracleToolID: oracleToolID,
            scope: scope,
            issuer: issuer,
            inputArtifacts: inputArtifacts,
            primaryOutputArtifacts: primaryOutputArtifacts,
            oracleOutputArtifacts: oracleOutputArtifacts,
            cases: cases.map {
            ToolOracleCaseComparison(
                caseID: $0.caseID,
                primary: $0.primary,
                oracle: $0.oracle,
                agreementComparisons: $0.agreementComparisons
            )
            },
            checkedAt: checkedAt,
            schemaVersion: schemaVersion
        )
        return try ToolQualificationCanonicalJSON.encode(normalized)
    }

    public static func decodeCanonical(from data: Data) throws -> Self {
        let result = try ToolQualificationCanonicalJSON.decode(Self.self, from: data)
        guard result.isStructurallyValid, try result.canonicalData() == data else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput("oracle result is not canonical")
        }
        return result
    }
}
