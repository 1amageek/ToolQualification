import Foundation
import Testing
import ToolQualification
import ToolQualificationCLICore
import XcircuitePackage

@Suite("ToolQualification process evidence build CLI")
struct ToolQualificationBuildProcessEvidenceCLITests {
    @Test("build-process-evidence writes a qualified record")
    func writesQualifiedRecord() throws {
        let directory = try makeTemporaryDirectory()
        let now = Date(timeIntervalSince1970: 1_000)
        let request = makeRequest(now: now, independenceVerified: true)
        let inputURL = directory.appending(path: "build-request.json")
        let outputURL = directory.appending(path: "process-evidence.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(request).write(to: inputURL, options: .atomic)

        let result = ToolQualificationCLI.invoke(arguments: [
            "build-process-evidence",
            "--input", inputURL.path,
            "--output", outputURL.path,
            "--at", "1000",
            "--pretty",
        ])

        #expect(result.exitCode == 0)
        #expect(FileManager.default.fileExists(atPath: outputURL.path))
        let envelope = try JSONDecoder().decode(
            ToolQualificationBuildProcessEvidenceEnvelope.self,
            from: Data(result.standardOutput.utf8)
        )
        #expect(envelope.qualified)
        #expect(envelope.outputPath == outputURL.path)
        let evidence = try JSONDecoder().decode(
            ToolProcessQualificationEvidence.self,
            from: Data(contentsOf: outputURL)
        )
        #expect(evidence.isQualified(at: now, requirePDKScope: true))
        #expect(evidence.qualifiedModelIDs == ["process-model-a"])
    }

    @Test("build-process-evidence returns a blocked envelope without writing output")
    func blocksWithoutIndependence() throws {
        let directory = try makeTemporaryDirectory()
        let now = Date(timeIntervalSince1970: 1_000)
        let request = makeRequest(now: now, independenceVerified: false)
        let inputURL = directory.appending(path: "build-request.json")
        let outputURL = directory.appending(path: "process-evidence.json")
        try JSONEncoder().encode(request).write(to: inputURL, options: .atomic)

        let result = ToolQualificationCLI.invoke(arguments: [
            "build-process-evidence",
            "--input", inputURL.path,
            "--output", outputURL.path,
            "--at", "1000",
        ])

        #expect(result.exitCode == 2)
        #expect(!FileManager.default.fileExists(atPath: outputURL.path))
        let envelope = try JSONDecoder().decode(
            ToolQualificationBuildProcessEvidenceEnvelope.self,
            from: Data(result.standardOutput.utf8)
        )
        #expect(!envelope.qualified)
        #expect(envelope.diagnostics.contains {
            $0.contains("independenceVerified")
        })
    }

    @Test("build-process-evidence help exposes the artifact-backed contract")
    func helpDescribesCommand() {
        let result = ToolQualificationCLI.invoke(arguments: [
            "build-process-evidence", "--help",
        ])

        #expect(result.exitCode == 0)
        #expect(result.standardOutput.contains("--input"))
        #expect(result.standardOutput.contains("--output"))
        #expect(result.standardOutput.contains("independent"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "toolqualification-build-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeRequest(
        now: Date,
        independenceVerified: Bool
    ) -> ToolProcessQualificationEvidenceBuildRequest {
        let scope = ToolQualificationScope(
            implementationID: "qualified-scan",
            binaryDigest: String(repeating: "a", count: 64),
            algorithmVersion: "scan-v1",
            processProfileID: "fixture-process",
            deckDigest: String(repeating: "b", count: 64),
            pdkID: "fixture-pdk",
            pdkDigest: String(repeating: "c", count: 64)
        )
        let kinds: [ToolEvidenceKind] = [.corpus, .oracle, .healthCheck, .productionApproval]
        let artifacts = kinds.map { kind in
            XcircuiteFileReference(
                artifactID: "\(kind.rawValue)-artifact",
                path: "qualification/\(kind.rawValue).json",
                kind: .report,
                format: .json,
                sha256: String(repeating: "d", count: 64),
                byteCount: 1
            )
        }
        let evidence = kinds.enumerated().map { index, kind in
            ToolEvidence(
                evidenceID: kind.rawValue,
                kind: kind,
                artifact: artifacts[index],
                qualification: ToolEvidenceQualificationSummary(
                    qualified: true,
                    scope: scope,
                    qualificationID: "qualification-1",
                    independenceVerified: true
                ),
                checkedAt: now
            )
        }
        return ToolProcessQualificationEvidenceBuildRequest(
            qualificationID: "qualification-1",
            toolID: "dft-engine",
            scope: scope,
            corpusEvidence: [evidence[0]],
            oracleEvidence: [evidence[1]],
            healthEvidence: [evidence[2]],
            approvalEvidence: [evidence[3]],
            evidenceArtifacts: artifacts,
            qualifiedModelIDs: ["process-model-a"],
            independenceVerified: independenceVerified,
            qualifiedAt: now.addingTimeInterval(-10),
            expiresAt: now.addingTimeInterval(100)
        )
    }
}
