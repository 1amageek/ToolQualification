import CircuiteFoundation
import Foundation

public struct ToolQualificationRecordIssuanceRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let recordID: String
    public let descriptor: ToolDescriptor
    public let health: ToolHealthCheckResult
    public let issuer: ProducerIdentity
    public let issuedAt: Date

    public init(
        recordID: String,
        descriptor: ToolDescriptor,
        health: ToolHealthCheckResult,
        issuer: ProducerIdentity,
        issuedAt: Date,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.recordID = recordID
        self.descriptor = descriptor
        self.health = health
        self.issuer = issuer
        self.issuedAt = issuedAt
    }

    public var isStructurallyValid: Bool {
        schemaVersion == Self.currentSchemaVersion
            && !recordID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && health.toolID == descriptor.toolID
            && descriptor.isStructurallyValid
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case recordID
        case descriptor
        case health
        case issuer
        case issuedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        recordID = try container.decode(String.self, forKey: .recordID)
        descriptor = try container.decode(ToolDescriptor.self, forKey: .descriptor)
        health = try container.decode(ToolHealthCheckResult.self, forKey: .health)
        issuer = try container.decode(ProducerIdentity.self, forKey: .issuer)
        let issuedAtValue = try container.decode(String.self, forKey: .issuedAt)
        guard let parsedIssuedAt = Self.date(from: issuedAtValue) else {
            throw DecodingError.dataCorruptedError(
                forKey: .issuedAt,
                in: container,
                debugDescription: "issuedAt must be an ISO-8601 timestamp"
            )
        }
        issuedAt = parsedIssuedAt
        guard isStructurallyValid else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Qualification record issuance request is not structurally valid."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(recordID, forKey: .recordID)
        try container.encode(descriptor, forKey: .descriptor)
        try container.encode(health, forKey: .health)
        try container.encode(issuer, forKey: .issuer)
        try container.encode(Self.string(from: issuedAt), forKey: .issuedAt)
    }

    private static func date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
