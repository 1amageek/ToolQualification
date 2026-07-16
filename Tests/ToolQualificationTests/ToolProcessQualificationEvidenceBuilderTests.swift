import Foundation
import Testing
import CircuiteFoundation

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
            reading: LocalToolQualificationArtifactReader(workspaceRoot: fixture.root),
            at: now
        )

        #expect(evidence.status == .qualified)
        #expect(evidence.isQualified(at: now, requirePDKScope: true))
        #expect(evidence.hasIndependentOracleEvidence)
        #expect(evidence.evidenceArtifactIDs == request.evidenceArtifacts.map { $0.id.rawValue }.sorted())
        #expect(evidence.qualifiedModelIDs == ["process-model-a", "process-model-b"])
    }

    @Test("builder derives pass status and rejects a failed canonical corpus result")
    func rejectsFailedCorpusResult() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        var request = fixture.request(now: now)
        request.corpusResultArtifacts = [try fixture.failedCorpusResult(now: now)]

        await #expect(throws: ToolProcessQualificationEvidenceBuildError.self) {
            _ = try await ToolProcessQualificationEvidenceBuilder().build(
                request,
                reading: LocalToolQualificationArtifactReader(workspaceRoot: fixture.root),
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
                reading: LocalToolQualificationArtifactReader(workspaceRoot: fixture.root),
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
                reading: LocalToolQualificationArtifactReader(workspaceRoot: fixture.root),
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
                reading: LocalToolQualificationArtifactReader(workspaceRoot: fixture.root),
                at: now
            )
        }
    }

    @Test("persisted qualification contracts require their exact current schema")
    func rejectsMissingAndUnsupportedSchemaVersions() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        let request = fixture.request(now: now)
        let evidence = try await ToolProcessQualificationEvidenceBuilder().build(
            request,
            reading: LocalToolQualificationArtifactReader(workspaceRoot: fixture.root),
            at: now
        )

        try expectCurrentSchema(
            ToolCorpusQualificationResult.self,
            data: Data(contentsOf: fixture.root.appending(path: fixture.corpus.path))
        )
        try expectCurrentSchema(
            ToolOracleQualificationResult.self,
            data: Data(contentsOf: fixture.root.appending(path: fixture.oracle.path))
        )
        try expectCurrentSchema(
            ToolHealthQualificationResult.self,
            data: Data(contentsOf: fixture.root.appending(path: fixture.health.path))
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
    let issuer: ProducerIdentity

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tool-qualification-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let toolProducer = try ProducerIdentity(kind: .tool, identifier: "qualified-scan", version: "1.0.0")
        let oracleProducer = try ProducerIdentity(kind: .tool, identifier: "independent-scan-oracle", version: "2.0.0")
        let tool = try Self.artifact("tool", root: root, producer: toolProducer)
        let process = try Self.artifact("process", root: root)
        let pdk = try Self.artifact("pdk", root: root)
        let deck = try Self.artifact("deck", root: root)
        let oracleTool = try Self.artifact("oracle-tool", root: root, producer: oracleProducer)
        identity = ToolProcessQualificationArtifacts(
            toolExecutable: tool,
            processProfile: process,
            pdk: pdk,
            ruleDeck: deck,
            oracleExecutable: oracleTool
        )
        input = try Self.artifact("input", root: root)
        output = try Self.artifact("output", root: root)
        issuer = try ProducerIdentity(
            kind: .engine,
            identifier: "qualification-runner",
            version: "1.0.0"
        )
        scope = ToolQualificationScope(
            implementationID: "qualified-scan",
            toolVersion: "1.0.0",
            binaryDigest: tool.sha256,
            algorithmVersion: "scan-v1",
            processProfileID: "fixture-process",
            processProfileDigest: process.sha256,
            deckDigest: deck.sha256,
            pdkID: "fixture-pdk",
            pdkDigest: pdk.sha256,
            oracle: ToolOracleQualificationScope(
                implementationID: "independent-scan-oracle",
                version: "2.0.0",
                binaryDigest: oracleTool.sha256
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
                cases: [Self.passingCase("case-1")],
                checkedAt: checkedAt
            ).canonicalData(),
            producer: issuer
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
                oracleOutputArtifacts: [output],
                cases: [Self.passingOracleCase("case-1")],
                checkedAt: checkedAt
            ).canonicalData(),
            producer: issuer
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
            ).canonicalData(),
            producer: issuer
        )
    }

    func request(now: Date, qualifiedModelIDs: [String] = []) -> ToolProcessQualificationEvidenceBuildRequest {
        ToolProcessQualificationEvidenceBuildRequest(
            qualificationID: "qualification-1",
            toolID: "qualified-scan",
            scope: scope,
            identityArtifacts: identity,
            corpusResultArtifacts: [corpus],
            oracleResultArtifacts: [oracle],
            healthResultArtifacts: [health],
            inputArtifacts: [input],
            outputArtifacts: [output],
            qualifiedModelIDs: qualifiedModelIDs,
            qualifiedAt: now.addingTimeInterval(-10),
            expiresAt: now.addingTimeInterval(100)
        )
    }

    func failedCorpusResult(now: Date) throws -> ArtifactReference {
        try Self.artifact(
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
            ).canonicalData(),
            producer: issuer
        )
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

    private static func passingOracleCase(_ caseID: String) -> ToolOracleCaseComparison {
        ToolOracleCaseComparison(
            caseID: caseID,
            primary: passingCase(caseID),
            oracle: passingCase(caseID),
            agreementComparisons: [ToolQualificationMetricComparison(
                metricID: "agreement",
                observed: 0,
                expected: 0
            )]
        )
    }

    private static func artifact(
        _ name: String,
        root: URL,
        data: Data? = nil,
        producer: ProducerIdentity? = nil
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
            relativeTo: root,
            producer: producer
        )
    }
}
