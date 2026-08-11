import Foundation
import Testing
import CircuiteFoundation
import CircuiteFoundationCrypto
import CircuiteFoundationFileSystem
import CircuiteFoundationFoundation

@testable import ToolQualification

@Suite("Tool process qualification evidence builder")
struct ToolProcessQualificationEvidenceBuilderTests {
    @Test("builder verifies and promotes a complete independent artifact graph")
    func buildsQualifiedRecord() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        let request = fixture.request(now: now, qualifiedModelIDs: ["process-model-b", "process-model-a"])

        let evidence = try await ToolProcessQualificationEvidenceBuilder().build(
            request,
            reading: fixture.reader,
            at: now
        )

        #expect(evidence.status == .qualified)
        #expect(evidence.isQualified(at: now, requirePDKScope: true))
        #expect(evidence.hasIndependentOracleEvidence)
        #expect(evidence.evidenceArtifactIDs == request.evidenceArtifacts.map { $0.id.description }.sorted())
        #expect(evidence.qualifiedModelIDs == ["process-model-a", "process-model-b"])
    }

    @Test("builder requires corpus and independent oracle coverage for every requested corner")
    func requiresCompleteOperatingCornerCoverage() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        let qualified = fixture.request(
            now: now,
            requiredOperatingCornerIDs: ["tt", "ss", "ff"]
        )

        let evidence = try await ToolProcessQualificationEvidenceBuilder().build(
            qualified,
            reading: fixture.reader,
            at: now
        )
        #expect(evidence.qualifiedOperatingCornerIDs == ["ff", "ss", "tt"])

        let missing = fixture.request(
            now: now,
            requiredOperatingCornerIDs: ["tt", "ss", "ff", "sf"]
        )
        await #expect(throws: ToolProcessQualificationEvidenceBuildError.self) {
            _ = try await ToolProcessQualificationEvidenceBuilder().build(
                missing,
                reading: fixture.reader,
                at: now
            )
        }
    }

    @Test("builder derives pass status and rejects a failed canonical corpus result")
    func rejectsFailedCorpusResult() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        var request = fixture.request(now: now)
        request.corpusResultArtifacts = [try await fixture.failedCorpusResult(now: now)]

        await #expect(throws: ToolProcessQualificationEvidenceBuildError.self) {
            _ = try await ToolProcessQualificationEvidenceBuilder().build(
                request,
                reading: fixture.reader,
                at: now
            )
        }
    }

    @Test("builder rejects an artifact changed after it was referenced")
    func rejectsChangedArtifact() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        let request = fixture.request(now: now)
        try Data("changed".utf8).write(
            to: fixture.root.appendingPathComponent("qualification/oracle-evidence.json"),
            options: .atomic
        )

        do {
            _ = try await ToolProcessQualificationEvidenceBuilder().build(
                request,
                reading: fixture.reader,
                at: now
            )
            Issue.record("Changed evidence must not be promoted")
        } catch let error as ToolProcessQualificationEvidenceBuildError {
            #expect(error.localizedDescription.contains("integrity failed"))
        }
    }

    @Test("builder rejects an expired qualification window")
    func rejectsExpiredQualificationWindow() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        let request = fixture.request(now: now.addingTimeInterval(-200))

        await #expect(throws: ToolProcessQualificationEvidenceBuildError.notValidAt) {
            _ = try await ToolProcessQualificationEvidenceBuilder().build(
                request,
                reading: fixture.reader,
                at: now
            )
        }
    }

    @Test("builder rejects nonfinite qualification timestamps")
    func rejectsNonfiniteQualificationTimestamp() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        var request = fixture.request(now: now)
        request.expiresAt = Date(timeIntervalSinceReferenceDate: .infinity)

        await #expect(throws: ToolProcessQualificationEvidenceBuildError.self) {
            _ = try await ToolProcessQualificationEvidenceBuilder().build(
                request,
                reading: fixture.reader,
                at: now
            )
        }
    }

    @Test("builder rejects a qualification graph without an independent oracle result")
    func rejectsMissingOracleResult() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        var request = fixture.request(now: now)
        request.oracleResultArtifacts = []

        await #expect(throws: ToolProcessQualificationEvidenceBuildError.missingEvidence(.oracle)) {
            _ = try await ToolProcessQualificationEvidenceBuilder().build(
                request,
                reading: fixture.reader,
                at: now
            )
        }
    }

    @Test("oracle result requires distinct primary and oracle output artifacts")
    func rejectsSharedOracleOutputArtifact() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let result = ToolOracleQualificationResult(
            resultID: "oracle-shared-output",
            qualificationID: "qualification-1",
            primaryToolID: "qualified-scan",
            oracleToolID: "independent-scan-oracle",
            scope: fixture.scope,
            issuer: fixture.issuer,
            inputArtifacts: [fixture.input],
            primaryOutputArtifacts: [fixture.output],
            oracleOutputArtifacts: [fixture.output],
            cases: [Fixture.passingOracleCase("case-1")],
            checkedAt: Date(timeIntervalSince1970: 1_000)
        )

        #expect(!result.isStructurallyValid)
        #expect(throws: ToolProcessQualificationEvidenceBuildError.self) {
            _ = try result.canonicalData()
        }
    }

    @Test("oracle agreement values must be bound to both case outcomes")
    func rejectsUnboundOracleAgreementValues() throws {
        let primary = ToolQualificationCaseOutcome(
            caseID: "case-1",
            coverageTags: ["fixture"],
            comparisons: [ToolQualificationMetricComparison(
                metricID: "metric",
                observed: 0,
                expected: 0
            )]
        )
        let oracle = ToolQualificationCaseOutcome(
            caseID: "case-1",
            coverageTags: ["fixture"],
            comparisons: [ToolQualificationMetricComparison(
                metricID: "metric",
                observed: 1,
                expected: 1
            )]
        )
        let comparison = ToolOracleCaseComparison(
            caseID: "case-1",
            primary: primary,
            oracle: oracle,
            agreementComparisons: [ToolOracleMetricComparison(
                metricID: "metric",
                primaryObserved: 0,
                oracleObserved: 0
            )]
        )

        #expect(!comparison.isStructurallyValid)
        #expect(!comparison.agreed)
    }

    @Test("persisted qualification contracts require their exact current schema")
    func rejectsMissingAndUnsupportedSchemaVersions() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        let request = fixture.request(now: now)
        let evidence = try await ToolProcessQualificationEvidenceBuilder().build(
            request,
            reading: fixture.reader,
            at: now
        )

        try expectCurrentSchema(
            ToolCorpusQualificationResult.self,
            data: Data(contentsOf: fixture.root.appending(path: "qualification/corpus-evidence.json"))
        )
        try expectCurrentSchema(
            ToolOracleQualificationResult.self,
            data: Data(contentsOf: fixture.root.appending(path: "qualification/oracle-evidence.json"))
        )
        try expectCurrentSchema(
            ToolHealthQualificationResult.self,
            data: Data(contentsOf: fixture.root.appending(path: "qualification/health-evidence.json"))
        )
        try expectCurrentSchema(
            ToolProcessQualificationEvidenceBuildRequest.self,
            data: JSONEncoder().encode(request)
        )
        try expectCurrentSchema(
            ToolProcessQualificationEvidence.self,
            data: JSONEncoder().encode(evidence)
        )
    }

    private func expectCurrentSchema<Value: Decodable>(
        _ type: Value.Type,
        data: Data
    ) throws {
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        object.removeValue(forKey: "schemaVersion")
        let missing = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(type, from: missing)
        }

        object["schemaVersion"] = 9_999
        let unsupported = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(type, from: unsupported)
        }
    }
}

private struct Fixture {
    let root: URL
    let scope: ToolQualificationScope
    let identity: ToolProcessQualificationArtifacts
    let corpus: ArtifactReference
    let oracle: ArtifactReference
    let health: ArtifactReference
    let input: ArtifactReference
    let output: ArtifactReference
    let oracleOutput: ArtifactReference
    let issuer: ProducerIdentity
    let reader: VerifiedFileQualificationArtifactReader

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tool-qualification-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let tool = try Self.artifact("tool", root: root)
        let process = try Self.artifact("process", root: root)
        let pdk = try Self.artifact("pdk", root: root)
        let deck = try Self.artifact("deck", root: root)
        let oracleTool = try Self.artifact("oracle-tool", root: root)
        identity = ToolProcessQualificationArtifacts(
            toolExecutable: tool,
            processProfile: process,
            pdk: pdk,
            ruleDeck: deck,
            oracleExecutable: oracleTool
        )
        input = try Self.artifact("input", root: root)
        output = try Self.artifact("output", root: root)
        oracleOutput = try Self.artifact("oracle-output", root: root)
        issuer = try ProducerIdentity(
            kind: .engine,
            identifier: "qualification-runner",
            version: "1.0.0"
        )
        scope = ToolQualificationScope(
            implementationID: "qualified-scan",
            toolVersion: "1.0.0",
            binaryDigest: tool.digest.hexadecimalValue,
            algorithmVersion: "scan-v1",
            processProfileID: "fixture-process",
            processProfileDigest: process.digest.hexadecimalValue,
            deckDigest: deck.digest.hexadecimalValue,
            pdkID: "fixture-pdk",
            pdkDigest: pdk.digest.hexadecimalValue,
            oracle: ToolOracleQualificationScope(
                implementationID: "independent-scan-oracle",
                version: "2.0.0",
                binaryDigest: oracleTool.digest.hexadecimalValue
            )
        )
        let checkedAt = Date(timeIntervalSince1970: 1_000)
        corpus = try Self.artifact(
            "corpus-evidence",
            root: root,
            data: ToolCorpusQualificationResult(
                resultID: "corpus",
                qualificationID: "qualification-1",
                toolID: "qualified-scan",
                scope: scope,
                issuer: issuer,
                inputArtifacts: [input],
                outputArtifacts: [output],
                coverage: ToolQualificationCoverage(
                    operatingCornerIDs: ["tt", "ss", "ff"]
                ),
                cases: [Self.passingCase("case-1")],
                checkedAt: checkedAt
            ).canonicalData()
        )
        oracle = try Self.artifact(
            "oracle-evidence",
            root: root,
            data: ToolOracleQualificationResult(
                resultID: "oracle",
                qualificationID: "qualification-1",
                primaryToolID: "qualified-scan",
                oracleToolID: "independent-scan-oracle",
                scope: scope,
                issuer: issuer,
                inputArtifacts: [input],
                primaryOutputArtifacts: [output],
                oracleOutputArtifacts: [oracleOutput],
                coverage: ToolQualificationCoverage(
                    operatingCornerIDs: ["tt", "ss", "ff"]
                ),
                cases: [Self.passingOracleCase("case-1")],
                checkedAt: checkedAt
            ).canonicalData()
        )
        health = try Self.artifact(
            "health-evidence",
            root: root,
            data: ToolHealthQualificationResult(
                resultID: "health",
                qualificationID: "qualification-1",
                toolID: "qualified-scan",
                scope: scope,
                issuer: issuer,
                inputArtifacts: [input],
                outputArtifacts: [output],
                checkedAt: checkedAt
            ).canonicalData()
        )
        reader = VerifiedFileQualificationArtifactReader(urlsByArtifactID: [
            tool.id: Self.url("tool", root: root),
            process.id: Self.url("process", root: root),
            pdk.id: Self.url("pdk", root: root),
            deck.id: Self.url("deck", root: root),
            oracleTool.id: Self.url("oracle-tool", root: root),
            input.id: Self.url("input", root: root),
            output.id: Self.url("output", root: root),
            oracleOutput.id: Self.url("oracle-output", root: root),
            corpus.id: Self.url("corpus-evidence", root: root),
            oracle.id: Self.url("oracle-evidence", root: root),
            health.id: Self.url("health-evidence", root: root),
        ])
    }

    func request(
        now: Date,
        qualifiedModelIDs: [String] = [],
        requiredOperatingCornerIDs: [String] = []
    ) -> ToolProcessQualificationEvidenceBuildRequest {
        ToolProcessQualificationEvidenceBuildRequest(
            qualificationID: "qualification-1",
            toolID: "qualified-scan",
            scope: scope,
            identityArtifacts: identity,
            corpusResultArtifacts: [corpus],
            oracleResultArtifacts: [oracle],
            healthResultArtifacts: [health],
            inputArtifacts: [input],
            outputArtifacts: [output, oracleOutput],
            qualifiedModelIDs: qualifiedModelIDs,
            requiredOperatingCornerIDs: requiredOperatingCornerIDs,
            qualifiedAt: now.addingTimeInterval(-10),
            expiresAt: now.addingTimeInterval(100)
        )
    }

    func failedCorpusResult(now: Date) async throws -> ArtifactReference {
        let reference = try Self.artifact(
            "corpus-evidence",
            root: root,
            data: ToolCorpusQualificationResult(
                resultID: "corpus",
                qualificationID: "qualification-1",
                toolID: "qualified-scan",
                scope: scope,
                issuer: issuer,
                inputArtifacts: [input],
                outputArtifacts: [output],
                cases: [ToolQualificationCaseOutcome(
                    caseID: "case-1",
                    coverageTags: ["fixture"],
                    comparisons: [ToolQualificationMetricComparison(
                        metricID: "case-result",
                        observed: 1,
                        expected: 0
                    )]
                )],
                checkedAt: now
            ).canonicalData()
        )
        await reader.insert(
            Self.url("corpus-evidence", root: root),
            for: reference.id
        )
        return reference
    }

    func remove() {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove fixture: \(error.localizedDescription)")
        }
    }

    private static func passingCase(_ caseID: String) -> ToolQualificationCaseOutcome {
        ToolQualificationCaseOutcome(
            caseID: caseID,
            coverageTags: ["fixture"],
            comparisons: [ToolQualificationMetricComparison(
                metricID: "case-result",
                observed: 0,
                expected: 0
            )]
        )
    }

    fileprivate static func passingOracleCase(_ caseID: String) -> ToolOracleCaseComparison {
        ToolOracleCaseComparison(
            caseID: caseID,
            primary: passingCase(caseID),
            oracle: passingCase(caseID),
            agreementComparisons: [ToolOracleMetricComparison(
                metricID: "case-result",
                primaryObserved: 0,
                oracleObserved: 0
            )]
        )
    }

    private static func artifact(
        _ name: String,
        root: URL,
        data: Data? = nil
    ) throws -> ArtifactReference {
        let relativePath = "qualification/\(name).json"
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try (data ?? Data("artifact:\(name)".utf8)).write(to: url, options: .atomic)
        return try LocalArtifactReferencer().reference(
            ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: relativePath),
                role: .output,
                kind: .evidence,
                format: .json
            ),
            relativeTo: root
        )
    }

    private static func url(_ name: String, root: URL) -> URL {
        root.appending(path: "qualification/\(name).json")
    }
}

private actor VerifiedFileQualificationArtifactReader: ToolQualificationArtifactReading {
    private var urlsByArtifactID: [ArtifactID: URL]

    init(urlsByArtifactID: [ArtifactID: URL]) {
        self.urlsByArtifactID = urlsByArtifactID
    }

    func insert(_ url: URL, for artifactID: ArtifactID) {
        urlsByArtifactID[artifactID] = url
    }

    func verifiedData(for reference: ArtifactReference) async throws -> Data {
        guard let url = urlsByArtifactID[reference.id] else {
            throw ToolProcessQualificationEvidenceBuildError.artifactAvailabilityMissing(
                reference.id.description
            )
        }
        let data = try Data(contentsOf: url)
        let digest = try SHA256ContentDigester().digest(data: data, using: .sha256)
        guard digest == reference.digest,
              UInt64(data.count) == reference.byteCount else {
            throw ToolProcessQualificationEvidenceBuildError.artifactIntegrityFailed(
                reference.id.description
            )
        }
        return data
    }
}
