import Foundation
import Testing
import ToolQualification
import ToolQualificationCLICore

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
          "qualification": {
            "qualified": true,
            "policyID": "policy-\(kind)",
            "observedMetrics": {},
            "observedCounts": {},
            "failureCodes": []
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
          "requirePassingHealthCheck": \(requirePassingHealthCheck)
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

    @Test func evaluateEligibleToolExitsZero() throws {
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

        let result = ToolQualificationCLI.invoke(arguments: [
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

    @Test func evaluateWithPassingHealthCheckExitsZero() throws {
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

        let result = ToolQualificationCLI.invoke(arguments: [
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

    @Test func evaluateRejectedToolExitsTwo() throws {
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

        let result = ToolQualificationCLI.invoke(arguments: [
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

    @Test func evaluateRegistryRanksDecisionsAndSelectsFirstEligible() throws {
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

        let result = ToolQualificationCLI.invoke(arguments: [
            "evaluate-registry",
            "--descriptors", descriptorsPath,
            "--requirement", requirementPath,
        ])

        #expect(result.exitCode == 0)
        let envelope = try decodeStandardOutput(ToolQualificationRegistryEnvelope.self, from: result)
        // Eligible first, trust level descending, then toolID ascending;
        // rejected tools follow with the same secondary ordering.
        #expect(envelope.decisions.map(\.toolID) == ["z.high", "a.tool", "b.tool", "r.mismatch"])
        #expect(envelope.selectedToolID == "z.high")
        #expect(envelope.evaluatedCount == 4)
        #expect(envelope.eligibleCount == 3)
        let mismatch = try #require(envelope.decisions.last)
        #expect(!mismatch.eligible)
        #expect(mismatch.decision.diagnostics.contains { $0.code == "TOOL_KIND_MISMATCH" })
    }

    @Test func evaluateRegistryAppliesHealthResultsByToolID() throws {
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

        let result = ToolQualificationCLI.invoke(arguments: [
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

    @Test func evaluateRegistryWithNoEligibleToolExitsTwo() throws {
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

        let result = ToolQualificationCLI.invoke(arguments: [
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

    @Test func validateProcessEvidenceReportsQualifiedScopedRecord() throws {
        let directory = try makeTemporaryDirectory()
        let evidencePath = try write(
            """
            {
              "schemaVersion": 1,
              "qualificationID": "sky130-pex-production-v1",
              "toolID": "magic-pex",
              "scope": {
                "implementationID": "magic-pex",
                "binaryDigest": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                "algorithmVersion": "magic-8.3.652",
                "processProfileID": "sky130A",
                "deckDigest": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                "pdkID": "sky130A",
                "pdkDigest": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
              },
              "status": "qualified",
              "corpusEvidenceIDs": ["corpus"],
              "oracleEvidenceIDs": ["magic-pex"],
              "healthEvidenceIDs": ["magic-health"],
              "approvalEvidenceIDs": ["human-approval"],
              "evidenceArtifactIDs": ["qualification.json"],
              "independenceVerified": true,
              "blockers": [],
              "qualifiedAt": "1970-01-01T00:01:40.000Z",
              "expiresAt": "1970-01-01T00:03:20.000Z"
            }
            """,
            named: "process-evidence.json",
            in: directory
        )

        let result = ToolQualificationCLI.invoke(arguments: [
            "validate-process-evidence",
            "--evidence", evidencePath,
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

    @Test func validateProcessEvidenceRejectsMissingPDKScope() throws {
        let directory = try makeTemporaryDirectory()
        let evidencePath = try write(
            """
            {
              "schemaVersion": 1,
              "qualificationID": "qualification",
              "toolID": "native-tool",
              "scope": {
                "implementationID": "native-tool",
                "binaryDigest": "binary",
                "algorithmVersion": "algorithm",
                "processProfileID": "process",
                "deckDigest": "deck"
              },
              "status": "qualified",
              "corpusEvidenceIDs": ["corpus"],
              "oracleEvidenceIDs": ["oracle"],
              "healthEvidenceIDs": ["health"],
              "approvalEvidenceIDs": ["approval"],
              "evidenceArtifactIDs": ["record"],
              "independenceVerified": true,
              "blockers": [],
              "qualifiedAt": "1970-01-01T00:01:40.000Z",
              "expiresAt": "1970-01-01T00:03:20.000Z"
            }
            """,
            named: "process-evidence.json",
            in: directory
        )

        let result = ToolQualificationCLI.invoke(arguments: [
            "validate-process-evidence",
            "--evidence", evidencePath,
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

    // MARK: - Failure envelopes

    @Test func missingDescriptorFileEmitsUnreadableFileEnvelope() throws {
        let directory = try makeTemporaryDirectory()
        let requirementPath = try write(
            requirementJSON(),
            named: "requirement.json",
            in: directory
        )
        let missingPath = directory.appendingPathComponent("does-not-exist.json").path

        let result = ToolQualificationCLI.invoke(arguments: [
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

    @Test func invalidJSONEmitsInvalidJSONEnvelope() throws {
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

        let result = ToolQualificationCLI.invoke(arguments: [
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

    @Test func invalidArgumentsEmitInvalidArgumentsEnvelope() throws {
        let unknownFlag = ToolQualificationCLI.invoke(arguments: ["evaluate", "--bogus"])
        #expect(unknownFlag.exitCode == 1)
        let unknownFlagDiagnostic = try decodeDiagnostic(from: unknownFlag)
        #expect(unknownFlagDiagnostic.code == "toolqualification.cli.invalid-arguments")

        let missingRequired = ToolQualificationCLI.invoke(arguments: ["evaluate"])
        #expect(missingRequired.exitCode == 1)
        let missingRequiredDiagnostic = try decodeDiagnostic(from: missingRequired)
        #expect(missingRequiredDiagnostic.code == "toolqualification.cli.invalid-arguments")
        #expect(missingRequiredDiagnostic.message.contains("--descriptor"))

        let noCommand = ToolQualificationCLI.invoke(arguments: [])
        #expect(noCommand.exitCode == 1)
        let noCommandDiagnostic = try decodeDiagnostic(from: noCommand)
        #expect(noCommandDiagnostic.code == "toolqualification.cli.invalid-arguments")

        let unknownCommand = ToolQualificationCLI.invoke(arguments: ["frobnicate"])
        #expect(unknownCommand.exitCode == 1)
        let unknownCommandDiagnostic = try decodeDiagnostic(from: unknownCommand)
        #expect(unknownCommandDiagnostic.code == "toolqualification.cli.invalid-arguments")
    }

    // MARK: - Help

    @Test func helpTextListsCommandsAndExitCodes() {
        let general = ToolQualificationCLI.invoke(arguments: ["--help"])
        #expect(general.exitCode == 0)
        #expect(general.standardError.isEmpty)
        #expect(general.standardOutput.contains("evaluate"))
        #expect(general.standardOutput.contains("evaluate-registry"))
        #expect(general.standardOutput.contains("EXIT CODES"))

        let evaluate = ToolQualificationCLI.invoke(arguments: ["evaluate", "--help"])
        #expect(evaluate.exitCode == 0)
        #expect(evaluate.standardOutput.contains("--descriptor"))
        #expect(evaluate.standardOutput.contains("--requirement"))
        #expect(evaluate.standardOutput.contains("--health"))

        let registry = ToolQualificationCLI.invoke(arguments: ["evaluate-registry", "--help"])
        #expect(registry.exitCode == 0)
        #expect(registry.standardOutput.contains("--descriptors"))
        #expect(registry.standardOutput.contains("--health-results"))
        #expect(registry.standardOutput.contains("selectedToolID"))

        let process = ToolQualificationCLI.invoke(arguments: ["validate-process-evidence", "--help"])
        #expect(process.exitCode == 0)
        #expect(process.standardOutput.contains("--require-pdk"))
        #expect(process.standardOutput.contains("--at"))
    }
}
