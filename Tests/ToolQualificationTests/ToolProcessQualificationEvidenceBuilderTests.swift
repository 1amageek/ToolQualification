import Foundation
import Testing
import XcircuitePackage

@testable import ToolQualification

@Suite("Tool process qualification evidence builder")
struct ToolProcessQualificationEvidenceBuilderTests {
    @Test("builder promotes independent scoped evidence into a qualified record")
    func buildsQualifiedRecord() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let scope = makeScope()
        let artifacts = [
            makeArtifact(id: "corpus-artifact"),
            makeArtifact(id: "oracle-artifact"),
            makeArtifact(id: "health-artifact"),
            makeArtifact(id: "approval-artifact"),
        ]
        let request = makeRequest(
            now: now,
            scope: scope,
            artifacts: artifacts,
            qualifiedModelIDs: ["process-model-b", "process-model-a"],
            corpus: [makeEvidence(id: "corpus", kind: .corpus, scope: scope, artifact: artifacts[0])],
            oracle: [makeEvidence(id: "oracle", kind: .oracle, scope: scope, artifact: artifacts[1])],
            health: [makeEvidence(id: "health", kind: .healthCheck, scope: scope, artifact: artifacts[2])],
            approval: [makeEvidence(id: "approval", kind: .productionApproval, scope: scope, artifact: artifacts[3])]
        )

        let evidence = try ToolProcessQualificationEvidenceBuilder().build(request, at: now)

        #expect(evidence.status == .qualified)
        #expect(evidence.isQualified(at: now, requirePDKScope: true))
        #expect(evidence.corpusEvidenceIDs == ["corpus"])
        #expect(evidence.oracleEvidenceIDs == ["oracle"])
        #expect(evidence.healthEvidenceIDs == ["health"])
        #expect(evidence.approvalEvidenceIDs == ["approval"])
        #expect(evidence.evidenceArtifactIDs == artifacts.map { $0.artifactID ?? $0.path }.sorted())
        #expect(evidence.qualifiedModelIDs == ["process-model-a", "process-model-b"])
    }

    @Test("builder rejects evidence that is not independently qualified")
    func rejectsUnqualifiedEvidence() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let scope = makeScope()
        let artifact = makeArtifact(id: "corpus-artifact")
        let unqualified = ToolEvidence(
            evidenceID: "corpus",
            kind: .corpus,
            artifact: artifact,
            qualification: ToolEvidenceQualificationSummary(
                qualified: true,
                scope: scope,
                independenceVerified: false
            ),
            checkedAt: now
        )
        let request = makeRequest(
            now: now,
            scope: scope,
            artifacts: [artifact],
            corpus: [unqualified],
            oracle: [makeEvidence(id: "oracle", kind: .oracle, scope: scope, artifact: artifact)],
            health: [makeEvidence(id: "health", kind: .healthCheck, scope: scope, artifact: artifact)],
            approval: [makeEvidence(id: "approval", kind: .productionApproval, scope: scope, artifact: artifact)]
        )

        do {
            _ = try ToolProcessQualificationEvidenceBuilder().build(request, at: now)
            Issue.record("Unqualified evidence must not be promoted")
        } catch let error as ToolProcessQualificationEvidenceBuildError {
            #expect(error == .evidenceNotQualified("corpus"))
        }
    }

    @Test("builder rejects an evidence artifact that is not bound to an evidence item")
    func rejectsUnreferencedArtifact() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let scope = makeScope()
        let corpusArtifact = makeArtifact(id: "corpus-artifact")
        let unusedArtifact = makeArtifact(id: "unused-artifact")
        let request = makeRequest(
            now: now,
            scope: scope,
            artifacts: [corpusArtifact, unusedArtifact],
            corpus: [makeEvidence(id: "corpus", kind: .corpus, scope: scope, artifact: corpusArtifact)],
            oracle: [makeEvidence(id: "oracle", kind: .oracle, scope: scope, artifact: corpusArtifact)],
            health: [makeEvidence(id: "health", kind: .healthCheck, scope: scope, artifact: corpusArtifact)],
            approval: [makeEvidence(id: "approval", kind: .productionApproval, scope: scope, artifact: corpusArtifact)]
        )

        do {
            _ = try ToolProcessQualificationEvidenceBuilder().build(request, at: now)
            Issue.record("Unreferenced evidence artifacts must be rejected")
        } catch let error as ToolProcessQualificationEvidenceBuildError {
            #expect(error.localizedDescription.contains("every evidence artifact"))
        }
    }

    @Test("builder rejects an expired qualification window")
    func rejectsExpiredQualificationWindow() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let scope = makeScope()
        let artifact = makeArtifact(id: "corpus-artifact")
        let request = makeRequest(
            now: now.addingTimeInterval(-200),
            scope: scope,
            artifacts: [artifact],
            corpus: [makeEvidence(id: "corpus", kind: .corpus, scope: scope, artifact: artifact)],
            oracle: [makeEvidence(id: "oracle", kind: .oracle, scope: scope, artifact: artifact)],
            health: [makeEvidence(id: "health", kind: .healthCheck, scope: scope, artifact: artifact)],
            approval: [makeEvidence(id: "approval", kind: .productionApproval, scope: scope, artifact: artifact)]
        )

        do {
            _ = try ToolProcessQualificationEvidenceBuilder().build(request, at: now)
            Issue.record("Expired qualification evidence must not be promoted")
        } catch let error as ToolProcessQualificationEvidenceBuildError {
            #expect(error == .notValidAt)
        }
    }

    private func makeRequest(
        now: Date,
        scope: ToolQualificationScope,
        artifacts: [XcircuiteFileReference],
        qualifiedModelIDs: [String] = [],
        corpus: [ToolEvidence],
        oracle: [ToolEvidence],
        health: [ToolEvidence],
        approval: [ToolEvidence]
    ) -> ToolProcessQualificationEvidenceBuildRequest {
        ToolProcessQualificationEvidenceBuildRequest(
            qualificationID: "qualification-1",
            toolID: "dft-engine",
            scope: scope,
            corpusEvidence: corpus,
            oracleEvidence: oracle,
            healthEvidence: health,
            approvalEvidence: approval,
            evidenceArtifacts: artifacts,
            qualifiedModelIDs: qualifiedModelIDs,
            independenceVerified: true,
            qualifiedAt: now.addingTimeInterval(-10),
            expiresAt: now.addingTimeInterval(100)
        )
    }

    private func makeScope() -> ToolQualificationScope {
        ToolQualificationScope(
            implementationID: "qualified-scan",
            binaryDigest: String(repeating: "a", count: 64),
            algorithmVersion: "scan-v1",
            processProfileID: "fixture-process",
            deckDigest: String(repeating: "b", count: 64),
            pdkID: "fixture-pdk",
            pdkDigest: String(repeating: "c", count: 64)
        )
    }

    private func makeEvidence(
        id: String,
        kind: ToolEvidenceKind,
        scope: ToolQualificationScope,
        artifact: XcircuiteFileReference
    ) -> ToolEvidence {
        ToolEvidence(
            evidenceID: id,
            kind: kind,
            artifact: artifact,
            qualification: ToolEvidenceQualificationSummary(
                qualified: true,
                observedCounts: ["passed": 1],
                scope: scope,
                qualificationID: "qualification-1",
                independenceVerified: true
            ),
            checkedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    private func makeArtifact(id: String) -> XcircuiteFileReference {
        XcircuiteFileReference(
            artifactID: id,
            path: "qualification/\(id).json",
            kind: .report,
            format: .json,
            sha256: String(repeating: "d", count: 64),
            byteCount: 1
        )
    }
}
