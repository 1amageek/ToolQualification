import CircuiteFoundation
import Foundation

public struct ToolQualificationRecord: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let recordID: String
    public let descriptor: ToolDescriptor
    public let health: ToolHealthCheckResult
    public let issuanceDecisions: [ToolQualificationRecordDecision]
    public let issuer: ProducerIdentity
    public let issuedAt: Date

    init(
        recordID: String,
        descriptor: ToolDescriptor,
        health: ToolHealthCheckResult,
        issuanceDecisions: [ToolQualificationRecordDecision],
        issuer: ProducerIdentity,
        issuedAt: Date,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.recordID = recordID
        self.descriptor = descriptor
        self.health = health
        self.issuanceDecisions = issuanceDecisions.sorted { $0.operationID < $1.operationID }
        self.issuer = issuer
        self.issuedAt = issuedAt
    }

    public var isStructurallyValid: Bool {
        schemaVersion == Self.currentSchemaVersion
            && !recordID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && health.toolID == descriptor.toolID
            && descriptor.isStructurallyValid
            && issuanceDecisions.count == descriptor.capabilities.count
            && Set(issuanceDecisions.map(\.operationID)).count == issuanceDecisions.count
            && Set(issuanceDecisions.map(\.operationID)) == Set(descriptor.capabilities.map(\.operationID))
            && issuanceDecisions.allSatisfy {
                $0.decision.toolID == descriptor.toolID && $0.decision.status == .eligible
            }
    }

    public func canonicalData() throws -> Data {
        guard isStructurallyValid else {
            throw ToolQualificationRecordError.invalidStructure
        }
        return try ToolQualificationCanonicalJSON.encode(self)
    }

    public static func decodeCanonical(from data: Data) throws -> Self {
        let record = try ToolQualificationCanonicalJSON.decode(Self.self, from: data)
        guard record.isStructurallyValid else {
            throw ToolQualificationRecordError.invalidStructure
        }
        return record
    }
}
