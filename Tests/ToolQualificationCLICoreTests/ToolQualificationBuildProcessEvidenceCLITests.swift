import Foundation
import Testing
import CircuiteFoundation
import CircuiteFoundationFileSystem
import CircuiteFoundationFoundation
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
        let inventoryURL = try ToolQualificationCLIArtifactFixture()
            .writeQualificationDirectoryInventory(root: directory)
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
            "--availability-inventory", inventoryURL.path,
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
        #expect(evidence.qualifiedModelIDs == ["process-model-a"])
        #expect(evidence.outputArtifacts.count == 4)
    }

    @Test("CLI refuses requested model coverage absent from original execution receipts")
    func refusesUnexecutedRequestedModel() async throws {
        let directory = try makeTemporaryDirectory()
        defer { remove(directory) }
        let now = Date(timeIntervalSince1970: 1_000)
        var request = try makeRequest(now: now, root: directory, independent: true)
        request.qualifiedModelIDs = ["never-executed-model"]
        let inventoryURL = try ToolQualificationCLIArtifactFixture().writeQualificationDirectoryInventory(root: directory)
        let inputURL = directory.appending(path: "build-request.json")
        let outputURL = directory.appending(path: "process-evidence.json")
        try JSONEncoder().encode(request).write(to: inputURL, options: .atomic)
        let result = await ToolQualificationCLI.invoke(arguments: ["build-process-evidence",
            "--input", inputURL.path, "--output", outputURL.path, "--workspace-root", directory.path,
            "--availability-inventory", inventoryURL.path, "--at", "1000"])
        #expect(result.exitCode == 2)
        #expect(!FileManager.default.fileExists(atPath: outputURL.path))
        #expect(result.standardOutput.contains("never-executed-model"))
        #expect(result.standardOutput.contains("matched executed receipts"))
    }

    @Test("CLI verifies nested original receipt bytes before writing evidence")
    func refusesAlteredOriginalReceipt() async throws {
        let directory = try makeTemporaryDirectory()
        defer { remove(directory) }
        let now = Date(timeIntervalSince1970: 1_000)
        let request = try makeRequest(now: now, root: directory, independent: true)
        let inventoryURL = try ToolQualificationCLIArtifactFixture().writeQualificationDirectoryInventory(root: directory)
        let inputURL = directory.appending(path: "build-request.json")
        let outputURL = directory.appending(path: "process-evidence.json")
        try JSONEncoder().encode(request).write(to: inputURL, options: .atomic)
        try Data("altered receipt".utf8).write(
            to: directory.appending(path: "qualification/output-receipt-0.json"), options: .atomic)
        let result = await ToolQualificationCLI.invoke(arguments: ["build-process-evidence",
            "--input", inputURL.path, "--output", outputURL.path, "--workspace-root", directory.path,
            "--availability-inventory", inventoryURL.path, "--at", "1000"])
        #expect(result.exitCode == 2)
        #expect(!FileManager.default.fileExists(atPath: outputURL.path))
        #expect(result.standardOutput.contains("artifact"))
    }

    @Test("build-process-evidence derives and rejects a non-independent oracle")
    func blocksWithoutIndependentOracle() async throws {
        let directory = try makeTemporaryDirectory()
        defer { remove(directory) }
        let now = Date(timeIntervalSince1970: 1_000)
        let request = try makeRequest(now: now, root: directory, independent: false)
        let inventoryURL = try ToolQualificationCLIArtifactFixture()
            .writeQualificationDirectoryInventory(root: directory)
        let inputURL = directory.appending(path: "build-request.json")
        let outputURL = directory.appending(path: "process-evidence.json")
        try JSONEncoder().encode(request).write(to: inputURL, options: .atomic)

        let result = await ToolQualificationCLI.invoke(arguments: [
            "build-process-evidence",
            "--input", inputURL.path,
            "--output", outputURL.path,
            "--workspace-root", directory.path,
            "--availability-inventory", inventoryURL.path,
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
        #expect(result.standardOutput.contains("--availability-inventory"))
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
        let oracleID = "independent-scan-oracle"
        let tool = try artifact("tool", root: root)
        let process = try artifact("process", root: root)
        let pdk = try artifact("pdk", root: root)
        let deck = try artifact("deck", root: root)
        let oracleTool = try artifact("oracle-tool", root: root)
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
            binaryDigest: tool.digest.hexadecimalValue,
            algorithmVersion: "scan-v1",
            processProfileID: "fixture-process",
            processProfileDigest: process.digest.hexadecimalValue,
            deckDigest: deck.digest.hexadecimalValue,
            pdkID: "fixture-pdk",
            pdkDigest: pdk.digest.hexadecimalValue,
            oracle: ToolOracleQualificationScope(
                implementationID: oracleID,
                version: "2.0.0",
                binaryDigest: oracleTool.digest.hexadecimalValue
            )
        )
        let input = try artifact("input", root: root)
        let source = try artifact("model-source", root: root)
        let inputs = [input, source]
        let artifactFixture = try ToolQualificationCLIArtifactFixture()
        let primaryExecution = try artifactFixture.writeExecution(root: root, caseID: "case-1",
            executionID: "output", implementationID: scope.implementationID, version: scope.toolVersion,
            executable: tool, inputs: inputs, source: source, modelIDs: ["process-model-a"],
            observations: ["case-result": 0])
        let oracleExecution = try artifactFixture.writeExecution(root: root, caseID: "case-1",
            executionID: "oracle-output", implementationID: oracleID, version: "2.0.0",
            executable: oracleTool, inputs: inputs, source: source, modelIDs: ["process-model-a"],
            observations: ["case-result": 0])
        let output = primaryExecution.original
        let oracleOutput = oracleExecution.original
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
                inputArtifacts: inputs,
                outputArtifacts: [output] + primaryExecution.receipts,
                cases: [ToolQualificationCaseOutcome(
                    caseID: "case-1",
                    originalExecutionArtifact: output,
                    coverageTags: ["fixture"],
                    comparisons: [ToolQualificationMetricComparison(
                        metricID: "case-result",
                        observed: 0,
                        expected: 0
                    )]
                )],
                checkedAt: now
            ).canonicalData()
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
                inputArtifacts: inputs,
                primaryOutputArtifacts: [output] + primaryExecution.receipts,
                oracleOutputArtifacts: [oracleOutput] + oracleExecution.receipts,
                cases: [ToolOracleCaseComparison(
                    caseID: "case-1",
                    primary: ToolQualificationCaseOutcome(
                        caseID: "case-1",
                        originalExecutionArtifact: output,
                        coverageTags: ["fixture"],
                        comparisons: [ToolQualificationMetricComparison(metricID: "case-result", observed: 0, expected: 0)]
                    ),
                    oracle: ToolQualificationCaseOutcome(
                        caseID: "case-1",
                        originalExecutionArtifact: oracleOutput,
                        coverageTags: ["fixture"],
                        comparisons: [ToolQualificationMetricComparison(metricID: "case-result", observed: 0, expected: 0)]
                    ),
                    agreementComparisons: [ToolOracleMetricComparison(
                        metricID: "case-result",
                        primaryObserved: 0,
                        oracleObserved: 0
                    )]
                )],
                checkedAt: now
            ).canonicalData()
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
                inputArtifacts: inputs,
                outputArtifacts: [output],
                checkedAt: now
            ).canonicalData()
        )
        var request = ToolProcessQualificationEvidenceBuildRequest(
            qualificationID: "qualification-1",
            toolID: "qualified-scan",
            scope: scope,
            identityArtifacts: identity,
            corpusResultArtifacts: [corpus],
            oracleResultArtifacts: [oracle],
            healthResultArtifacts: [health],
            inputArtifacts: inputs,
            outputArtifacts: [output, oracleOutput] + primaryExecution.receipts + oracleExecution.receipts,
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
        data: Data? = nil
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
            relativeTo: root
        )
    }
}
