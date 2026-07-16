import Foundation
import Testing
import CircuiteFoundation

@testable import ToolQualification

@Suite("Tool process qualification evidence")
struct ToolProcessQualificationEvidenceTests {
    @Test("process evidence retains typed identity and evidence artifacts")
    func processEvidenceRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("process-evidence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: root) }
            catch { Issue.record("Failed to remove fixture: \(error.localizedDescription)") }
        }
        let toolProducer = try ProducerIdentity(kind: .tool, identifier: "magic-pex", version: "8.3.489")
        let oracleProducer = try ProducerIdentity(kind: .tool, identifier: "calibre-pex", version: "2026.1")
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
            implementationID: "magic-pex",
            toolVersion: "8.3.489",
            binaryDigest: tool.sha256,
            algorithmVersion: "driver-v1",
            processProfileID: "sky130A",
            processProfileDigest: process.sha256,
            deckDigest: deck.sha256,
            pdkID: "sky130A",
            pdkDigest: pdk.sha256,
            oracle: ToolOracleQualificationScope(
                implementationID: "calibre-pex",
                version: "2026.1",
                binaryDigest: oracleTool.sha256
            )
        )
        let artifacts = try ["corpus", "oracle", "health", "input", "output"]
            .map { try artifact($0, root: root) }
        let evidence = ToolProcessQualificationEvidence(
            qualificationID: "process-qualification",
            toolID: "magic-pex",
            scope: scope,
            identityArtifacts: identity,
            status: .qualified,
            corpusEvidence: [item("corpus", kind: .corpus, artifact: artifacts[0])],
            oracleEvidence: [item("oracle", kind: .oracle, artifact: artifacts[1])],
            healthEvidence: [item("health", kind: .healthCheck, artifact: artifacts[2])],
            inputArtifacts: [artifacts[3]],
            outputArtifacts: [artifacts[4]],
            qualifiedAt: Date(timeIntervalSince1970: 100),
            expiresAt: Date(timeIntervalSince1970: 200)
        )

        #expect(evidence.isStructurallyValid)
        #expect(evidence.isQualified(at: Date(timeIntervalSince1970: 150)))
        let encoded = try JSONEncoder().encode(evidence)
        let decoded = try JSONDecoder().decode(ToolProcessQualificationEvidence.self, from: encoded)
        #expect(decoded == evidence)
        #expect(decoded.identityArtifacts == identity)

        var mismatchedIdentity = identity
        mismatchedIdentity.toolExecutable = ArtifactReference(
            locator: tool.locator,
            digest: tool.digest,
            byteCount: tool.byteCount
        )
        let mismatchedProducer = ToolProcessQualificationEvidence(
            qualificationID: evidence.qualificationID,
            toolID: evidence.toolID,
            scope: evidence.scope,
            identityArtifacts: mismatchedIdentity,
            status: evidence.status,
            corpusEvidence: evidence.corpusEvidence,
            oracleEvidence: evidence.oracleEvidence,
            healthEvidence: evidence.healthEvidence,
            inputArtifacts: evidence.inputArtifacts,
            outputArtifacts: evidence.outputArtifacts,
            qualifiedAt: evidence.qualifiedAt,
            expiresAt: evidence.expiresAt
        )
        #expect(!mismatchedProducer.isStructurallyValid)

    }

    private func item(
        _ id: String,
        kind: ToolEvidenceKind,
        artifact: ArtifactReference
    ) -> ToolEvidence {
        ToolEvidence(
            evidenceID: id,
            kind: kind,
            artifact: artifact,
            checkedAt: Date(timeIntervalSince1970: 100)
        )
    }

    private func artifact(
        _ id: String,
        root: URL,
        producer: ProducerIdentity? = nil
    ) throws -> ArtifactReference {
        let path = "qualification/\(id).json"
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(id.utf8).write(to: url, options: .atomic)
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
