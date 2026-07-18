import CircuiteFoundation
import Foundation
import Testing

@testable import ToolQualification

@Suite("Tool qualification record authority")
struct ToolQualificationRecordTests {
    @Test func issuerCreatesCanonicalRecordForEveryCapability() async throws {
        let fixture = try RecordFixture()
        let record = try await fixture.issue()

        #expect(record.isStructurallyValid)
        #expect(record.issuanceDecisions.map(\.operationID) == ["inspect", "run"])
        #expect(record.issuanceDecisions.allSatisfy { $0.decision.status == .eligible })
        #expect(try ToolQualificationRecord.decodeCanonical(from: record.canonicalData()) == record)
    }

    @Test func issuerRejectsFailedHealth() async throws {
        let fixture = try RecordFixture()

        await #expect(throws: ToolQualificationRecordError.issuanceRejected(
            toolID: fixture.descriptor.toolID,
            operationID: "inspect"
        )) {
            _ = try await fixture.issue(health: .failed)
        }
    }

    @Test func issuerRejectsDuplicateCapabilityIdentifiers() async throws {
        let fixture = try RecordFixture()
        var descriptor = fixture.descriptor
        descriptor.capabilities = [
            ToolCapability(operationID: "run"),
            ToolCapability(operationID: "run"),
        ]

        await #expect(throws: ToolQualificationRecordError.invalidStructure) {
            _ = try await DefaultToolQualificationRecordIssuer().issue(
                recordID: "duplicate-capabilities",
                descriptor: descriptor,
                health: ToolHealthCheckResult(toolID: descriptor.toolID, status: .passed),
                issuer: fixture.issuer,
                reading: fixture.reader,
                issuedAt: fixture.issuedAt
            )
        }
    }

    @Test func issuerRejectsBlankRecordIdentifier() async throws {
        let fixture = try RecordFixture()

        await #expect(throws: ToolQualificationRecordError.invalidStructure) {
            _ = try await DefaultToolQualificationRecordIssuer().issue(
                recordID: "  ",
                descriptor: fixture.descriptor,
                health: ToolHealthCheckResult(toolID: fixture.descriptor.toolID, status: .passed),
                issuer: fixture.issuer,
                reading: fixture.reader,
                issuedAt: fixture.issuedAt
            )
        }
    }

    @Test func validatorAcceptsIssuerBoundCanonicalRecord() async throws {
        let fixture = try RecordFixture()
        let record = try await fixture.issue()
        let reference = try await fixture.store(record: record, producer: fixture.issuer)

        let validated = try await ToolQualificationRecordValidator().validatedRecord(
            referencedBy: reference,
            expectedToolID: fixture.descriptor.toolID,
            reading: fixture.reader
        )

        #expect(validated == record)
    }

    @Test func validatorRejectsMismatchedToolIdentity() async throws {
        let fixture = try RecordFixture()
        let record = try await fixture.issue()
        let reference = try await fixture.store(record: record, producer: fixture.issuer)

        await #expect(throws: ToolQualificationRecordError.toolIdentityMismatch(
            expected: "other-tool",
            actual: fixture.descriptor.toolID
        )) {
            _ = try await ToolQualificationRecordValidator().validatedRecord(
                referencedBy: reference,
                expectedToolID: "other-tool",
                reading: fixture.reader
            )
        }
    }

    @Test func validatorRejectsReferenceIssuedByDifferentProducer() async throws {
        let fixture = try RecordFixture()
        let record = try await fixture.issue()
        let other = try ProducerIdentity(kind: .engine, identifier: "other-issuer", version: "1")
        let reference = try await fixture.store(record: record, producer: other)

        await #expect(throws: ToolQualificationRecordError.issuerMismatch) {
            _ = try await ToolQualificationRecordValidator().validatedRecord(
                referencedBy: reference,
                expectedToolID: fixture.descriptor.toolID,
                reading: fixture.reader
            )
        }
    }

    @Test func canonicalDecoderRejectsUnsupportedSchema() async throws {
        let fixture = try RecordFixture()
        let issued = try await fixture.issue()
        let unsupported = ToolQualificationRecord(
            recordID: issued.recordID,
            descriptor: issued.descriptor,
            health: issued.health,
            issuanceDecisions: issued.issuanceDecisions,
            issuer: issued.issuer,
            issuedAt: issued.issuedAt,
            schemaVersion: ToolQualificationRecord.currentSchemaVersion + 1
        )

        #expect(throws: ToolQualificationRecordError.invalidStructure) {
            _ = try unsupported.canonicalData()
        }
    }

    @Test func structuralValidationRejectsIncompleteDecisions() async throws {
        let fixture = try RecordFixture()
        let issued = try await fixture.issue()
        let incomplete = ToolQualificationRecord(
            recordID: issued.recordID,
            descriptor: issued.descriptor,
            health: issued.health,
            issuanceDecisions: Array(issued.issuanceDecisions.prefix(1)),
            issuer: issued.issuer,
            issuedAt: issued.issuedAt
        )

        #expect(!incomplete.isStructurallyValid)
        #expect(throws: ToolQualificationRecordError.invalidStructure) {
            _ = try incomplete.canonicalData()
        }
    }
}

private struct RecordFixture {
    let descriptor: ToolDescriptor
    let issuer: ProducerIdentity
    let reader = RecordArtifactReader()
    let issuedAt = Date(timeIntervalSince1970: 1_000)

    init() throws {
        issuer = try ProducerIdentity(kind: .engine, identifier: "tool-qualification", version: "1")
        descriptor = ToolDescriptor(
            toolID: "record-tool",
            displayName: "Record Tool",
            kind: .drc,
            version: "1.0.0",
            capabilities: [
                ToolCapability(operationID: "run"),
                ToolCapability(operationID: "inspect"),
            ],
            trustProfile: ToolTrustProfile(level: .unknown),
            environment: ToolEnvironment(platform: "macOS", requiredAssets: [])
        )
    }

    func issue(health status: ToolHealthStatus = .passed) async throws -> ToolQualificationRecord {
        try await DefaultToolQualificationRecordIssuer().issue(
            recordID: "record-1",
            descriptor: descriptor,
            health: ToolHealthCheckResult(toolID: descriptor.toolID, status: status),
            issuer: issuer,
            reading: reader,
            issuedAt: issuedAt
        )
    }

    func store(
        record: ToolQualificationRecord,
        producer: ProducerIdentity
    ) async throws -> ArtifactReference {
        let data = try record.canonicalData()
        let digest = try SHA256ContentDigester().digest(data: data, using: .sha256)
        let reference = ArtifactReference(
            id: try ArtifactID(rawValue: "record-artifact"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: "qualification/record.json"),
                role: .output,
                kind: .report,
                format: .json
            ),
            digest: digest,
            byteCount: UInt64(data.count),
            producer: producer
        )
        await reader.insert(data, for: reference)
        return reference
    }
}

private actor RecordArtifactReader: ToolQualificationArtifactReading {
    private var storedData: [ArtifactReference: Data] = [:]

    func insert(_ data: Data, for reference: ArtifactReference) {
        storedData[reference] = data
    }

    func verifiedData(for reference: ArtifactReference) async throws -> Data {
        guard let data = storedData[reference] else {
            throw ToolQualificationRecordError.invalidStructure
        }
        return data
    }
}
