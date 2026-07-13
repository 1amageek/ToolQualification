import Foundation
import Testing

@testable import ToolQualification

@Suite("Tool process qualification evidence")
struct ToolProcessQualificationEvidenceTests {
    @Test("process evidence uses ISO-8601 dates and reads legacy reference-date numbers")
    func processEvidenceDateCoding() throws {
        let scope = ToolQualificationScope(
            implementationID: "magic-pex",
            binaryDigest: String(repeating: "a", count: 64),
            algorithmVersion: "driver-v1",
            processProfileID: "sky130A",
            deckDigest: String(repeating: "b", count: 64),
            pdkID: "sky130A",
            pdkDigest: String(repeating: "c", count: 64)
        )
        let evidence = ToolProcessQualificationEvidence(
            qualificationID: "process-qualification",
            toolID: "magic-pex",
            scope: scope,
            status: .qualified,
            corpusEvidenceIDs: ["corpus"],
            oracleEvidenceIDs: ["oracle"],
            healthEvidenceIDs: ["health"],
            approvalEvidenceIDs: ["approval"],
            evidenceArtifactIDs: ["record"],
            independenceVerified: true,
            qualifiedAt: Date(timeIntervalSince1970: 100),
            expiresAt: Date(timeIntervalSince1970: 200)
        )
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(evidence)
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        #expect(object?["qualifiedAt"] as? String == "1970-01-01T00:01:40.000Z")
        #expect(object?["expiresAt"] as? String == "1970-01-01T00:03:20.000Z")

        let decoded = try JSONDecoder().decode(
            ToolProcessQualificationEvidence.self,
            from: encoded
        )
        #expect(decoded == evidence)

        let legacy = """
        {
          "schemaVersion": 1,
          "qualificationID": "legacy",
          "toolID": "magic-pex",
          "scope": {
            "implementationID": "magic-pex",
            "binaryDigest": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "algorithmVersion": "driver-v1",
            "processProfileID": "sky130A",
            "deckDigest": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            "pdkID": "sky130A",
            "pdkDigest": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
          },
          "status": "qualified",
          "corpusEvidenceIDs": ["corpus"],
          "oracleEvidenceIDs": ["oracle"],
          "healthEvidenceIDs": ["health"],
          "approvalEvidenceIDs": ["approval"],
          "evidenceArtifactIDs": ["record"],
          "independenceVerified": true,
          "blockers": [],
          "qualifiedAt": 100,
          "expiresAt": 200
        }
        """
        let legacyEvidence = try JSONDecoder().decode(
            ToolProcessQualificationEvidence.self,
            from: Data(legacy.utf8)
        )
        #expect(legacyEvidence.qualifiedAt == Date(timeIntervalSinceReferenceDate: 100))
        #expect(legacyEvidence.expiresAt == Date(timeIntervalSinceReferenceDate: 200))
    }
}
