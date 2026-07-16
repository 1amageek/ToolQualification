import Foundation
import Testing
import CircuiteFoundation
import ToolQualification
import ToolQualificationCLICore

@Suite("ToolQualification process evidence build CLI")
struct ToolQualificationBuildProcessEvidenceCLITests {
    @Test("build-process-evidence verifies artifacts and writes a qualified record")
    func writesQualifiedRecord() async throws {
        let directory = try makeTemporaryDirectory()
        defer { remove(directory) }
        let now = Date(timeIntervalSince1970: 1_000)
        let request = try makeRequest(now: now, root: directory, independent: true)
        let inputURL = directory.appending(path: "build-request.json")
        let outputURL = directory.appending(path: "process-evidence.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(request).write(to: inputURL, options: .atomic)

        let result = await ToolQualificationCLI.invoke(arguments: [
            "build-process-evidence",
            "--input", inputURL.path,
            "--output", outputURL.path,
            "--workspace-root", directory.path,
            "--at", "1000",
            "--pretty",
        ])

        #expect(result.exitCode == 0)
        let evidence = try JSONDecoder().decode(
            ToolProcessQualificationEvidence.self,
            from: Data(contentsOf: outputURL)
        )
        #expect(evidence.isQualified(at: now, requirePDKScope: true))
        #expect(evidence.hasIndependentOracleEvidence)
    }

    @Test("build-process-evidence derives and rejects a non-independent oracle")
    func blocksWithoutIndependentOracle() async throws {
        let directory = try makeTemporaryDirectory()
        defer { remove(directory) }
        let now = Date(timeIntervalSince1970: 1_000)
        let request = try makeRequest(now: now, root: directory, independent: false)
        let inputURL = directory.appending(path: "build-request.json")
        let outputURL = directory.appending(path: "process-evidence.json")
        try JSONEncoder().encode(request).write(to: inputURL, options: .atomic)

        let result = await ToolQualificationCLI.invoke(arguments: [
            "build-process-evidence",
            "--input", inputURL.path,
            "--output", outputURL.path,
            "--workspace-root", directory.path,
            "--at", "1000",
        ])

        #expect(result.exitCode == 2)
        #expect(!FileManager.default.fileExists(atPath: outputURL.path))
        #expect(result.standardOutput.contains("independent oracle scope"))
    }

    @Test("build-process-evidence help exposes artifact verification")
    func helpDescribesCommand() async {
        let result = await ToolQualificationCLI.invoke(arguments: ["build-process-evidence", "--help"])
        #expect(result.exitCode == 0)
        #expect(result.standardOutput.contains("--workspace-root"))
        #expect(result.standardOutput.contains("independent"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "toolqualification-build-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func remove(_ directory: URL) {
        do { try FileManager.default.removeItem(at: directory) }
        catch { Issue.record("Failed to remove fixture: \(error.localizedDescription)") }
    }

    private func makeRequest(
        now: Date,
        root: URL,
        independent: Bool
    ) throws -> ToolProcessQualificationEvidenceBuildRequest {
        let toolProducer = try ProducerIdentity(kind: .tool, identifier: "qualified-scan", version: "1.0.0")
        let oracleID = "independent-scan-oracle"
        let oracleProducer = try ProducerIdentity(kind: .tool, identifier: oracleID, version: "2.0.0")
        let tool = try artifact("tool", root: root, producer: toolProducer)
        let process = try artifact("process", root: root)
        let pdk = try artifact("pdk", root: root)
        let deck = try artifact("deck", root: root)
        let oracleTool = try artifact("oracle-tool", root: root, producer: oracleProducer)
        let identity = ToolProcessQualificationArtifacts(
            toolExecutable: tool,
            processProfile: process,
            pdk: pdk,
            ruleDeck: deck,
            oracleExecutable: oracleTool
        )
        let scope = ToolQualificationScope(
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
                implementationID: oracleID,
                version: "2.0.0",
                binaryDigest: oracleTool.sha256
            )
        )
        let input = try artifact("input", root: root)
        let output = try artifact("output", root: root)
        let issuer = try ProducerIdentity(
            kind: .engine,
            identifier: "qualification-runner",
            version: "1.0.0"
        )
        let corpus = try artifact(
            "corpus",
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
                        observed: 0,
                        expected: 0
                    )]
                )],
                checkedAt: now
            ).canonicalData(),
            producer: issuer
        )
        let oracle = try artifact(
            "oracle",
            root: root,
            data: ToolOracleQualificationResult(
                resultID: "oracle",
                qualificationID: "qualification-1",
                primaryToolID: "qualified-scan",
                oracleToolID: oracleID,
                scope: scope,
                issuer: issuer,
                inputArtifacts: [input],
                primaryOutputArtifacts: [output],
                oracleOutputArtifacts: [output],
                cases: [ToolOracleCaseComparison(
                    caseID: "case-1",
                    primary: ToolQualificationCaseOutcome(
                        caseID: "case-1",
                        coverageTags: ["fixture"],
                        comparisons: [ToolQualificationMetricComparison(metricID: "primary", observed: 0, expected: 0)]
                    ),
                    oracle: ToolQualificationCaseOutcome(
                        caseID: "case-1",
                        coverageTags: ["fixture"],
                        comparisons: [ToolQualificationMetricComparison(metricID: "oracle", observed: 0, expected: 0)]
                    ),
                    agreementComparisons: [ToolQualificationMetricComparison(metricID: "agreement", observed: 0, expected: 0)]
                )],
                checkedAt: now
            ).canonicalData(),
            producer: issuer
        )
        let health = try artifact(
            "health",
            root: root,
            data: ToolHealthQualificationResult(
                resultID: "health",
                qualificationID: "qualification-1",
                toolID: "qualified-scan",
                scope: scope,
                issuer: issuer,
                inputArtifacts: [input],
                outputArtifacts: [output],
                checkedAt: now
            ).canonicalData(),
            producer: issuer
        )
        var request = ToolProcessQualificationEvidenceBuildRequest(
            qualificationID: "qualification-1",
            toolID: "qualified-scan",
            scope: scope,
            identityArtifacts: identity,
            corpusResultArtifacts: [corpus],
            oracleResultArtifacts: [oracle],
            healthResultArtifacts: [health],
            inputArtifacts: [input],
            outputArtifacts: [output],
            qualifiedModelIDs: ["process-model-a"],
            qualifiedAt: now.addingTimeInterval(-10),
            expiresAt: now.addingTimeInterval(100)
        )
        if !independent {
            request.scope.oracle = ToolOracleQualificationScope(
                implementationID: request.toolID,
                version: request.scope.toolVersion,
                binaryDigest: request.scope.binaryDigest
            )
        }
        return request
    }

    private func artifact(
        _ name: String,
        root: URL,
        data: Data? = nil,
        producer: ProducerIdentity? = nil
    ) throws -> ArtifactReference {
        let path = "qualification/\(name).json"
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if data != nil || !FileManager.default.fileExists(atPath: url.path) {
            try (data ?? Data(name.utf8)).write(to: url, options: .atomic)
        }
        return try LocalArtifactReferencer().reference(
            ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: path),
                role: .output,
                kind: .evidence,
                format: .json
            ),
            relativeTo: root,
            producer: producer
        )
    }
}
