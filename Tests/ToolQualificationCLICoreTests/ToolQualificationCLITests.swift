import Foundation
import Testing
import ToolQualification
import ToolQualificationCLICore
import CircuiteFoundation

@Suite("ToolQualificationCLITests")
struct ToolQualificationCLITests {

    // MARK: - Fixtures

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("toolqualification-cli-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ contents: String, named name: String, in directory: URL) throws -> String {
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    private func evidenceJSON(toolID: String, kind: String) -> String {
        """
        {
          "evidenceID": "\(toolID)-\(kind)",
          "kind": "\(kind)",
          "artifact": {
            "id": "\(toolID)-\(kind)-artifact",
            "locator": {
              "location": { "storage": "workspaceRelative", "value": "qualification/\(toolID)-\(kind).json" },
              "role": "output",
              "kind": "evidence",
              "format": "json"
            },
            "digest": {
              "algorithm": "sha256",
              "hexadecimalValue": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
            },
            "byteCount": 1
          }
        }
        """
    }

    private func descriptorJSON(
        toolID: String,
        kind: String = "simulation",
        level: String = "smokeChecked",
        operationID: String = "simulate.transient",
        evidenceKinds: [String] = ["smoke"]
    ) -> String {
        let evidence = evidenceKinds
            .map { evidenceJSON(toolID: toolID, kind: $0) }
            .joined(separator: ",\n")
        return """
        {
          "toolID": "\(toolID)",
          "displayName": "\(toolID) display name",
          "kind": "\(kind)",
          "version": "1.0.0",
          "capabilities": [
            {
              "operationID": "\(operationID)",
              "inputFormats": ["SPICE"],
              "outputFormats": ["RAW"],
              "limitations": []
            }
          ],
          "trustProfile": {
            "level": "\(level)",
            "evidence": [\(evidence)],
            "knownLimitations": []
          },
          "environment": {
            "platform": "macOS",
            "requiredAssets": []
          }
        }
        """
    }

    private func requirementJSON(
        kind: String = "simulation",
        operationID: String = "simulate.transient",
        minimumLevel: String = "smokeChecked",
        requirePassingHealthCheck: Bool = false
    ) -> String {
        """
        {
          "kind": "\(kind)",
          "operationID": "\(operationID)",
          "minimumLevel": "\(minimumLevel)",
          "requiredInputFormats": [],
          "requiredOutputFormats": [],
          "requiredEvidenceKinds": [],
          "requiredQualifiedEvidenceKinds": [],
          "requirePassingHealthCheck": \(requirePassingHealthCheck),
          "requireIndependentQualificationEvidence": false
        }
        """
    }

    private func healthJSON(toolID: String, status: String = "passed") -> String {
        """
        {
          "toolID": "\(toolID)",
          "status": "\(status)",
          "diagnostics": [],
          "evidence": []
        }
        """
    }

    private func decodeStandardOutput<Envelope: Decodable>(
        _ type: Envelope.Type,
        from result: ToolQualificationCLIInvocationResult
    ) throws -> Envelope {
        try JSONDecoder().decode(Envelope.self, from: Data(result.standardOutput.utf8))
    }

    private func decodeDiagnostic(
        from result: ToolQualificationCLIInvocationResult
    ) throws -> ToolQualificationCLIDiagnosticEnvelope {
        try JSONDecoder().decode(
            ToolQualificationCLIDiagnosticEnvelope.self,
            from: Data(result.standardError.utf8)
        )
    }

    // MARK: - evaluate

    @Test func evaluateEligibleToolExitsZero() async throws {
        let directory = try makeTemporaryDirectory()
        let descriptorPath = try write(
            descriptorJSON(toolID: "sim.corespice"),
            named: "descriptor.json",
            in: directory
        )
        let requirementPath = try write(
            requirementJSON(),
            named: "requirement.json",
            in: directory
        )

        let result = await ToolQualificationCLI.invoke(arguments: [
            "evaluate",
            "--descriptor", descriptorPath,
            "--requirement", requirementPath,
        ])

        #expect(result.exitCode == 0)
        #expect(result.standardError.isEmpty)
        let envelope = try decodeStandardOutput(ToolQualificationEvaluateEnvelope.self, from: result)
        #expect(envelope.command == "evaluate")
        #expect(envelope.toolID == "sim.corespice")
        #expect(envelope.eligible)
        #expect(envelope.decision.status == .eligible)
        #expect(envelope.inputs.descriptorPath == descriptorPath)
        #expect(envelope.inputs.requirementPath == requirementPath)
        #expect(envelope.inputs.healthPath == nil)
    }

    @Test func evaluateWithPassingHealthCheckExitsZero() async throws {
        let directory = try makeTemporaryDirectory()
        let descriptorPath = try write(
            descriptorJSON(toolID: "sim.corespice"),
            named: "descriptor.json",
            in: directory
        )
        let requirementPath = try write(
            requirementJSON(requirePassingHealthCheck: true),
            named: "requirement.json",
            in: directory
        )
        let healthPath = try write(
            healthJSON(toolID: "sim.corespice"),
            named: "health.json",
            in: directory
        )

        let result = await ToolQualificationCLI.invoke(arguments: [
            "evaluate",
            "--descriptor", descriptorPath,
            "--requirement", requirementPath,
            "--health", healthPath,
        ])

        #expect(result.exitCode == 0)
        let envelope = try decodeStandardOutput(ToolQualificationEvaluateEnvelope.self, from: result)
        #expect(envelope.eligible)
        #expect(envelope.inputs.healthToolID == "sim.corespice")
        #expect(envelope.inputs.healthStatus == .passed)
    }

    @Test func evaluateRejectedToolExitsTwo() async throws {
        let directory = try makeTemporaryDirectory()
        let descriptorPath = try write(
            descriptorJSON(toolID: "sim.corespice", level: "smokeChecked"),
            named: "descriptor.json",
            in: directory
        )
        let requirementPath = try write(
            requirementJSON(minimumLevel: "oracleChecked"),
            named: "requirement.json",
            in: directory
        )

        let result = await ToolQualificationCLI.invoke(arguments: [
            "evaluate",
            "--descriptor", descriptorPath,
            "--requirement", requirementPath,
        ])

        #expect(result.exitCode == 2)
        let envelope = try decodeStandardOutput(ToolQualificationEvaluateEnvelope.self, from: result)
        #expect(!envelope.eligible)
        #expect(envelope.decision.status == .rejected)
        #expect(envelope.decision.diagnostics.contains { $0.code == "INSUFFICIENT_TRUST_LEVEL" })
    }

    // MARK: - evaluate-registry

    @Test func evaluateRegistryRanksDecisionsAndSelectsFirstEligible() async throws {
        let directory = try makeTemporaryDirectory()
        let descriptorsPath = try write(
            """
            [
              \(descriptorJSON(toolID: "b.tool")),
              \(descriptorJSON(toolID: "z.high", level: "oracleChecked", evidenceKinds: ["smoke", "corpus", "oracle"])),
              \(descriptorJSON(toolID: "r.mismatch", kind: "layout", level: "unknown", evidenceKinds: [])),
              \(descriptorJSON(toolID: "a.tool"))
            ]
            """,
            named: "descriptors.json",
            in: directory
        )
        let requirementPath = try write(
            requirementJSON(),
            named: "requirement.json",
            in: directory
        )

        let result = await ToolQualificationCLI.invoke(arguments: [
            "evaluate-registry",
            "--descriptors", descriptorsPath,
            "--requirement", requirementPath,
        ])

        #expect(result.exitCode == 0)
        let envelope = try decodeStandardOutput(ToolQualificationRegistryEnvelope.self, from: result)
        // Smoke-only descriptors remain eligible; an oracle-level claim fails
        // closed because its retained raw corpus and oracle results are not read.
        #expect(envelope.decisions.map(\.toolID) == ["a.tool", "b.tool", "z.high", "r.mismatch"])
        #expect(envelope.selectedToolID == "a.tool")
        #expect(envelope.evaluatedCount == 4)
        #expect(envelope.eligibleCount == 2)
        let mismatch = try #require(envelope.decisions.last)
        #expect(!mismatch.eligible)
        #expect(mismatch.decision.diagnostics.contains { $0.code == "TOOL_KIND_MISMATCH" })
    }

    @Test func evaluateRegistryAppliesHealthResultsByToolID() async throws {
        let directory = try makeTemporaryDirectory()
        let descriptorsPath = try write(
            """
            [
              \(descriptorJSON(toolID: "a.tool")),
              \(descriptorJSON(toolID: "b.tool")),
              \(descriptorJSON(toolID: "z.high", level: "oracleChecked", evidenceKinds: ["smoke", "corpus", "oracle"]))
            ]
            """,
            named: "descriptors.json",
            in: directory
        )
        let requirementPath = try write(
            requirementJSON(requirePassingHealthCheck: true),
            named: "requirement.json",
            in: directory
        )
        let healthResultsPath = try write(
            """
            {
              "a.tool": \(healthJSON(toolID: "a.tool"))
            }
            """,
            named: "health-results.json",
            in: directory
        )

        let result = await ToolQualificationCLI.invoke(arguments: [
            "evaluate-registry",
            "--descriptors", descriptorsPath,
            "--requirement", requirementPath,
            "--health-results", healthResultsPath,
        ])

        #expect(result.exitCode == 0)
        let envelope = try decodeStandardOutput(ToolQualificationRegistryEnvelope.self, from: result)
        // Only a.tool has a passing health check; the others are rejected and
        // ranked below it (trust level descending among the rejected).
        #expect(envelope.decisions.map(\.toolID) == ["a.tool", "z.high", "b.tool"])
        #expect(envelope.selectedToolID == "a.tool")
        #expect(envelope.eligibleCount == 1)
    }

    @Test func evaluateRegistryWithNoEligibleToolExitsTwo() async throws {
        let directory = try makeTemporaryDirectory()
        let descriptorsPath = try write(
            """
            [
              \(descriptorJSON(toolID: "a.tool")),
              \(descriptorJSON(toolID: "b.tool"))
            ]
            """,
            named: "descriptors.json",
            in: directory
        )
        let requirementPath = try write(
            requirementJSON(kind: "layout"),
            named: "requirement.json",
            in: directory
        )

        let result = await ToolQualificationCLI.invoke(arguments: [
            "evaluate-registry",
            "--descriptors", descriptorsPath,
            "--requirement", requirementPath,
        ])

        #expect(result.exitCode == 2)
        let envelope = try decodeStandardOutput(ToolQualificationRegistryEnvelope.self, from: result)
        #expect(envelope.selectedToolID == nil)
        #expect(envelope.eligibleCount == 0)
        #expect(envelope.evaluatedCount == 2)
    }

    // MARK: - validate-process-evidence

    @Test func validateProcessEvidenceReportsQualifiedScopedRecord() async throws {
        let directory = try makeTemporaryDirectory()
        let evidence = try await makeValidationEvidence(in: directory, includePDK: true)
        let evidenceURL = directory.appendingPathComponent("process-evidence.json")
        let encoder = JSONEncoder()
        try encoder.encode(evidence).write(to: evidenceURL, options: .atomic)

        let result = await ToolQualificationCLI.invoke(arguments: [
            "validate-process-evidence",
            "--evidence", evidenceURL.path,
            "--workspace-root", directory.path,
            "--require-pdk",
            "--at", "150",
        ])

        #expect(result.exitCode == 0)
        let envelope = try decodeStandardOutput(
            ToolQualificationProcessEvidenceEnvelope.self,
            from: result
        )
        #expect(envelope.qualified)
        #expect(envelope.structurallyValid)
        #expect(envelope.scope.pdkID == "sky130A")
        #expect(envelope.diagnostics.isEmpty)
    }

    @Test func validateProcessEvidenceRejectsMissingPDKScope() async throws {
        let directory = try makeTemporaryDirectory()
        let evidence = try await makeValidationEvidence(in: directory, includePDK: false)
        let evidenceURL = directory.appendingPathComponent("process-evidence.json")
        let encoder = JSONEncoder()
        try encoder.encode(evidence).write(to: evidenceURL, options: .atomic)

        let result = await ToolQualificationCLI.invoke(arguments: [
            "validate-process-evidence",
            "--evidence", evidenceURL.path,
            "--workspace-root", directory.path,
            "--require-pdk",
            "--at", "150",
        ])

        #expect(result.exitCode == 2)
        let envelope = try decodeStandardOutput(
            ToolQualificationProcessEvidenceEnvelope.self,
            from: result
        )
        #expect(!envelope.qualified)
        #expect(envelope.diagnostics.contains("process-evidence-pdk-scope-incomplete"))
    }

    private func makeValidationEvidence(
        in root: URL,
        includePDK: Bool
    ) async throws -> ToolProcessQualificationEvidence {
        let toolProducer = try ProducerIdentity(kind: .tool, identifier: "magic-pex", version: "8.3.652")
        let oracleProducer = try ProducerIdentity(kind: .tool, identifier: "calibre-pex", version: "2026.1")
        let tool = try validationArtifact("tool", root: root, producer: toolProducer)
        let process = try validationArtifact("process", root: root)
        let pdk = try validationArtifact("pdk", root: root)
        let deck = try validationArtifact("deck", root: root)
        let oracleTool = try validationArtifact("oracle-tool", root: root, producer: oracleProducer)
        let identity = ToolProcessQualificationArtifacts(
            toolExecutable: tool,
            processProfile: process,
            pdk: pdk,
            ruleDeck: deck,
            oracleExecutable: oracleTool
        )
        let scope = ToolQualificationScope(
            implementationID: "magic-pex",
            toolVersion: "8.3.652",
            binaryDigest: tool.digest.hexadecimalValue,
            algorithmVersion: "magic-driver-v2",
            processProfileID: "sky130A",
            processProfileDigest: process.digest.hexadecimalValue,
            deckDigest: deck.digest.hexadecimalValue,
            pdkID: "sky130A",
            pdkDigest: pdk.digest.hexadecimalValue,
            oracle: ToolOracleQualificationScope(
                implementationID: "calibre-pex",
                version: "2026.1",
                binaryDigest: oracleTool.digest.hexadecimalValue
            )
        )
        let input = try validationArtifact("input", root: root)
        let output = try validationArtifact("output", root: root)
        let issuer = try ProducerIdentity(kind: .engine, identifier: "qualification-runner", version: "1.0.0")
        let checkedAt = Date(timeIntervalSince1970: 120)
        let corpus = try validationArtifact(
            "corpus",
            root: root,
            data: ToolCorpusQualificationResult(
                resultID: "corpus",
                qualificationID: "sky130-pex-production-v1",
                toolID: "magic-pex",
                scope: scope,
                issuer: issuer,
                inputArtifacts: [input],
                outputArtifacts: [output],
                cases: [ToolQualificationCaseOutcome(
                    caseID: "case",
                    coverageTags: ["fixture"],
                    comparisons: [ToolQualificationMetricComparison(metricID: "case-result", observed: 0, expected: 0)]
                )],
                checkedAt: checkedAt
            ).canonicalData(),
            producer: issuer
        )
        let oracle = try validationArtifact(
            "oracle",
            root: root,
            data: ToolOracleQualificationResult(
                resultID: "oracle",
                qualificationID: "sky130-pex-production-v1",
                primaryToolID: "magic-pex",
                oracleToolID: "calibre-pex",
                scope: scope,
                issuer: issuer,
                inputArtifacts: [input],
                primaryOutputArtifacts: [output],
                oracleOutputArtifacts: [output],
                cases: [ToolOracleCaseComparison(
                    caseID: "case",
                    primary: ToolQualificationCaseOutcome(
                        caseID: "case",
                        coverageTags: ["fixture"],
                        comparisons: [ToolQualificationMetricComparison(metricID: "primary", observed: 0, expected: 0)]
                    ),
                    oracle: ToolQualificationCaseOutcome(
                        caseID: "case",
                        coverageTags: ["fixture"],
                        comparisons: [ToolQualificationMetricComparison(metricID: "oracle", observed: 0, expected: 0)]
                    ),
                    agreementComparisons: [ToolQualificationMetricComparison(metricID: "agreement", observed: 0, expected: 0)]
                )],
                checkedAt: checkedAt
            ).canonicalData(),
            producer: issuer
        )
        let health = try validationArtifact(
            "health",
            root: root,
            data: ToolHealthQualificationResult(
                resultID: "health",
                qualificationID: "sky130-pex-production-v1",
                toolID: "magic-pex",
                scope: scope,
                issuer: issuer,
                inputArtifacts: [input],
                outputArtifacts: [output],
                checkedAt: checkedAt
            ).canonicalData(),
            producer: issuer
        )
        let evidence = try await ToolProcessQualificationEvidenceBuilder().build(
            ToolProcessQualificationEvidenceBuildRequest(
                qualificationID: "sky130-pex-production-v1",
                toolID: "magic-pex",
                scope: scope,
                identityArtifacts: identity,
                corpusResultArtifacts: [corpus],
                oracleResultArtifacts: [oracle],
                healthResultArtifacts: [health],
                inputArtifacts: [input],
                outputArtifacts: [output],
                qualifiedAt: Date(timeIntervalSince1970: 100),
                expiresAt: Date(timeIntervalSince1970: 200)
            ),
            reading: LocalToolQualificationArtifactReader(workspaceRoot: root),
            at: Date(timeIntervalSince1970: 150)
        )
        guard !includePDK else { return evidence }
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(evidence)) as? [String: Any]
        )
        var encodedScope = try #require(object["scope"] as? [String: Any])
        encodedScope.removeValue(forKey: "pdkID")
        encodedScope.removeValue(forKey: "pdkDigest")
        object["scope"] = encodedScope
        return try JSONDecoder().decode(
            ToolProcessQualificationEvidence.self,
            from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        )
    }

    private func validationArtifact(
        _ id: String,
        root: URL,
        data: Data? = nil,
        producer: ProducerIdentity? = nil
    ) throws -> ArtifactReference {
        let path = "qualification/\(id).json"
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (data ?? Data(id.utf8)).write(to: url, options: .atomic)
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

    // MARK: - Failure envelopes

    @Test func missingDescriptorFileEmitsUnreadableFileEnvelope() async throws {
        let directory = try makeTemporaryDirectory()
        let requirementPath = try write(
            requirementJSON(),
            named: "requirement.json",
            in: directory
        )
        let missingPath = directory.appendingPathComponent("does-not-exist.json").path

        let result = await ToolQualificationCLI.invoke(arguments: [
            "evaluate",
            "--descriptor", missingPath,
            "--requirement", requirementPath,
        ])

        #expect(result.exitCode == 1)
        #expect(result.standardOutput.isEmpty)
        let diagnostic = try decodeDiagnostic(from: result)
        #expect(diagnostic.code == "toolqualification.cli.unreadable-file")
        #expect(diagnostic.message.contains(missingPath))
    }

    @Test func invalidJSONEmitsInvalidJSONEnvelope() async throws {
        let directory = try makeTemporaryDirectory()
        let descriptorPath = try write(
            "this is not json",
            named: "descriptor.json",
            in: directory
        )
        let requirementPath = try write(
            requirementJSON(),
            named: "requirement.json",
            in: directory
        )

        let result = await ToolQualificationCLI.invoke(arguments: [
            "evaluate",
            "--descriptor", descriptorPath,
            "--requirement", requirementPath,
        ])

        #expect(result.exitCode == 1)
        #expect(result.standardOutput.isEmpty)
        let diagnostic = try decodeDiagnostic(from: result)
        #expect(diagnostic.code == "toolqualification.cli.invalid-json")
        #expect(diagnostic.message.contains(descriptorPath))
    }

    @Test func invalidArgumentsEmitInvalidArgumentsEnvelope() async throws {
        let unknownFlag = await ToolQualificationCLI.invoke(arguments: ["evaluate", "--bogus"])
        #expect(unknownFlag.exitCode == 1)
        let unknownFlagDiagnostic = try decodeDiagnostic(from: unknownFlag)
        #expect(unknownFlagDiagnostic.code == "toolqualification.cli.invalid-arguments")

        let missingRequired = await ToolQualificationCLI.invoke(arguments: ["evaluate"])
        #expect(missingRequired.exitCode == 1)
        let missingRequiredDiagnostic = try decodeDiagnostic(from: missingRequired)
        #expect(missingRequiredDiagnostic.code == "toolqualification.cli.invalid-arguments")
        #expect(missingRequiredDiagnostic.message.contains("--descriptor"))

        let noCommand = await ToolQualificationCLI.invoke(arguments: [])
        #expect(noCommand.exitCode == 1)
        let noCommandDiagnostic = try decodeDiagnostic(from: noCommand)
        #expect(noCommandDiagnostic.code == "toolqualification.cli.invalid-arguments")

        let unknownCommand = await ToolQualificationCLI.invoke(arguments: ["frobnicate"])
        #expect(unknownCommand.exitCode == 1)
        let unknownCommandDiagnostic = try decodeDiagnostic(from: unknownCommand)
        #expect(unknownCommandDiagnostic.code == "toolqualification.cli.invalid-arguments")
    }

    // MARK: - Help

    @Test func helpTextListsCommandsAndExitCodes() async {
        let general = await ToolQualificationCLI.invoke(arguments: ["--help"])
        #expect(general.exitCode == 0)
        #expect(general.standardError.isEmpty)
        #expect(general.standardOutput.contains("evaluate"))
        #expect(general.standardOutput.contains("evaluate-registry"))
        #expect(general.standardOutput.contains("EXIT CODES"))

        let evaluate = await ToolQualificationCLI.invoke(arguments: ["evaluate", "--help"])
        #expect(evaluate.exitCode == 0)
        #expect(evaluate.standardOutput.contains("--descriptor"))
        #expect(evaluate.standardOutput.contains("--requirement"))
        #expect(evaluate.standardOutput.contains("--health"))

        let registry = await ToolQualificationCLI.invoke(arguments: ["evaluate-registry", "--help"])
        #expect(registry.exitCode == 0)
        #expect(registry.standardOutput.contains("--descriptors"))
        #expect(registry.standardOutput.contains("--health-results"))
        #expect(registry.standardOutput.contains("selectedToolID"))

        let process = await ToolQualificationCLI.invoke(arguments: ["validate-process-evidence", "--help"])
        #expect(process.exitCode == 0)
        #expect(process.standardOutput.contains("--require-pdk"))
        #expect(process.standardOutput.contains("--at"))
    }
}
