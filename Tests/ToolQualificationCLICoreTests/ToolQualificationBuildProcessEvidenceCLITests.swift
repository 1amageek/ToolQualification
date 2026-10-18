import Foundation
import Testing
import CircuiteFoundation
import CircuiteFoundationFileSystem
import CircuiteFoundationFoundation
import ToolQualification
import ToolQualificationCLICore

@Suite("ToolQualification process evidence build CLI")
struct ToolQualificationBuildProcessEvidenceCLITests {
    @Test("all five actual CLI commands consume an independently pinned retained policy", .timeLimit(.minutes(1)))
    func actualExecutableCommands() async throws {
        let environment = ProcessInfo.processInfo.environment
        let retainedRoot = environment["TOOLQUALIFICATION_CLI_EVIDENCE_ROOT"].map { URL(fileURLWithPath: $0) }
        let directory = try retainedRoot.map { $0.appending(path: "five-command") } ?? makeTemporaryDirectory()
        if retainedRoot != nil {
            #expect(!FileManager.default.fileExists(atPath: directory.path))
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        defer { if retainedRoot == nil { remove(directory) } }
        var executable = URL(fileURLWithPath: CommandLine.arguments[0])
        while executable.lastPathComponent != "debug" && executable.path != "/" {
            executable.deleteLastPathComponent()
        }
        executable.append(path: "toolqualification")
        if let path = environment["TOOLQUALIFICATION_EXECUTABLE_PATH"] { executable = URL(fileURLWithPath: path) }
        #expect(FileManager.default.isExecutableFile(atPath: executable.path))
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        let request = try makeRequest(now: now, root: directory, independent: true)
        let inventory = try ToolQualificationCLIArtifactFixture().writeQualificationDirectoryInventory(root: directory)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .deferredToDate
        func write<Value: Encodable>(_ name: String, _ value: Value) throws -> String {
            let url = directory.appending(path: name + ".json")
            try encoder.encode(value).write(to: url, options: .atomic)
            return url.path
        }
        let requestPath = try write("build-request", request)
        let evidencePath = directory.appending(path: "process-evidence.json").path
        let common = ["--workspace-root", directory.path, "--availability-inventory", inventory.path]
        #expect(try await launchCLI(executable, ["build-process-evidence", "--input", requestPath,
            "--output", evidencePath, "--at", String(now.timeIntervalSince1970)] + common,
            output: directory.appending(path: "01-build.stdout.json")) == 0)
        #expect(try await launchCLI(executable, ["validate-process-evidence", "--evidence", evidencePath,
            "--at", String(now.timeIntervalSince1970)] + common,
            output: directory.appending(path: "02-validate.stdout.json")) == 0)
        let decoder = JSONDecoder()
        let evidence = try decoder.decode(ToolProcessQualificationEvidence.self, from: Data(contentsOf: URL(fileURLWithPath: evidencePath)))
        let descriptor = ToolDescriptor(toolID: request.toolID, displayName: "Policy fixture", kind: .drc,
            version: request.scope.toolVersion, capabilities: [ToolCapability(operationID: "run-drc", inputFormats: [], outputFormats: [])],
            trustProfile: ToolTrustProfile(level: .productionEligible,
                evidence: evidence.corpusEvidence + evidence.oracleEvidence + evidence.healthEvidence,
                processQualification: evidence, assessmentPolicyArtifact: request.scope.assessmentPolicyArtifact),
            environment: ToolEnvironment(platform: "macOS", requiredAssets: []))
        let health = ToolHealthCheckResult(toolID: request.toolID, status: .passed)
        let requirement = ToolTrustRequirement(kind: .drc, operationID: "run-drc", minimumLevel: .productionEligible,
            qualificationScope: request.scope, requireIndependentQualificationEvidence: true)
        let descriptorPath = try write("descriptor", descriptor)
        let requirementPath = try write("requirement", requirement)
        let healthPath = try write("health", health)
        let issuance = try ToolQualificationRecordIssuanceRequest(recordID: "policy-fixture-record", descriptor: descriptor,
            health: health, issuer: ProducerIdentity(kind: .engine, identifier: "policy-fixture-issuer", version: "1"), issuedAt: now)
        #expect(try await launchCLI(executable, ["issue-record", "--input", try write("issuance", issuance),
            "--record-path", "issued-record.json", "--reference-output", directory.appending(path: "issued-reference.json").path] + common,
            output: directory.appending(path: "03-issue.stdout.json")) == 0)
        #expect(try await launchCLI(executable, ["evaluate", "--descriptor", descriptorPath,
            "--requirement", requirementPath, "--health", healthPath] + common,
            output: directory.appending(path: "04-evaluate.stdout.json")) == 0)
        #expect(try await launchCLI(executable, ["evaluate-registry", "--descriptors", try write("descriptors", [descriptor]),
            "--requirement", requirementPath, "--health-results", try write("health-results", [request.toolID: health])] + common,
            output: directory.appending(path: "05-registry.stdout.json")) == 0)
        let record = try ToolQualificationRecord.decodeCanonical(from: Data(contentsOf: directory.appending(path: "issued-record.json")))
        #expect(record.descriptor.trustProfile.processQualification == evidence)
        #expect(evidence.scope.assessmentPolicyArtifact == request.scope.assessmentPolicyArtifact)
        let criterion = try #require(request.scope.assessmentPolicyArtifact)
        let policyBinding = try #require(try JSONDecoder().decode(ToolQualificationCLIArtifactAvailabilityInventory.self,
            from: Data(contentsOf: inventory)).availabilities.first { $0.artifactID == criterion.id })
        guard case .local(_, _, let policyPath) = policyBinding else { Issue.record("Expected local policy input"); return }
        try FileManager.default.removeItem(at: directory.appending(path: policyPath.stringValue))
        #expect(try await launchCLI(executable, ["evaluate", "--descriptor", descriptorPath,
            "--requirement", requirementPath, "--health", healthPath] + common,
            output: directory.appending(path: "06-missing-policy.stdout.json")) == 2)
    }

    private func launchCLI(_ executable: URL, _ arguments: [String], output: URL) async throws -> Int32 {
        let process = Process(); process.executableURL = executable; process.arguments = arguments
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let file = try FileHandle(forWritingTo: output)
        process.standardOutput = file; process.standardError = file
        do {
            let code = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, any Error>) in
                process.terminationHandler = { completed in continuation.resume(returning: completed.terminationStatus) }
                do { try process.run() } catch { continuation.resume(throwing: error) }
            }
            try file.close()
            return code
        } catch {
            try file.close()
            throw error
        }
    }

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
        var scope = ToolQualificationScope(
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
        let assessment = try AssessmentFixture(root: root, caseID: "case-1", metricID: "case-result", originalInputs: inputs)
        scope.assessmentPolicyArtifact = assessment.policy
        let retainedInputs = inputs + assessment.inputs
        let artifactFixture = try ToolQualificationCLIArtifactFixture()
        let primaryExecution = try artifactFixture.writeExecution(root: root, caseID: "case-1",
            executionID: "output", implementationID: scope.implementationID, version: scope.toolVersion,
            executable: tool, inputs: inputs, source: source, modelIDs: ["process-model-a"],
            observations: ["case-result": 0], definitions: ["case-result": assessment.definition])
        let oracleExecution = try artifactFixture.writeExecution(root: root, caseID: "case-1",
            executionID: "oracle-output", implementationID: oracleID, version: "2.0.0",
            executable: oracleTool, inputs: inputs, source: source, modelIDs: ["process-model-a"],
            observations: ["case-result": 0], definitions: ["case-result": assessment.definition])
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
                inputArtifacts: retainedInputs,
                outputArtifacts: [output] + primaryExecution.receipts,
                cases: [ToolQualificationCaseOutcome(
                    caseID: "case-1",
                    originalExecutionArtifact: output,
                    coverageTags: ["fixture"],
                    comparisons: [ToolQualificationMetricComparison(
                        metricID: "case-result",
                        observed: 0,
                        expected: 0, criterionArtifact: assessment.primaryCriterion
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
                inputArtifacts: retainedInputs,
                primaryOutputArtifacts: [output] + primaryExecution.receipts,
                oracleOutputArtifacts: [oracleOutput] + oracleExecution.receipts,
                cases: [ToolOracleCaseComparison(
                    caseID: "case-1",
                    primary: ToolQualificationCaseOutcome(
                        caseID: "case-1",
                        originalExecutionArtifact: output,
                        coverageTags: ["fixture"],
                        comparisons: [ToolQualificationMetricComparison(metricID: "case-result", observed: 0, expected: 0, criterionArtifact: assessment.primaryCriterion)]
                    ),
                    oracle: ToolQualificationCaseOutcome(
                        caseID: "case-1",
                        originalExecutionArtifact: oracleOutput,
                        coverageTags: ["fixture"],
                        comparisons: [ToolQualificationMetricComparison(metricID: "case-result", observed: 0, expected: 0, criterionArtifact: assessment.primaryCriterion)]
                    ),
                    agreementComparisons: [ToolOracleMetricComparison(
                        metricID: "case-result",
                        primaryObserved: 0,
                        oracleObserved: 0, criterionArtifact: assessment.agreementCriterion
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
                inputArtifacts: retainedInputs,
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
            inputArtifacts: retainedInputs,
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
