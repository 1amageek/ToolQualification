import Foundation
import Testing
import ToolQualification

@Suite("Tool evidence Codable")
struct ToolEvidenceCodableTests {
    @Test func decodesISO8601CheckedAt() throws {
        let json = """
        {
          "evidenceID": "corpus-1",
          "kind": "corpus",
          "checkedAt": "2026-06-18T00:00:00Z"
        }
        """

        let evidence = try JSONDecoder().decode(
            ToolEvidence.self,
            from: Data(json.utf8)
        )

        #expect(evidence.checkedAt?.timeIntervalSince1970 == 1_781_740_800)
    }

    @Test func rejectsNumericCheckedAt() throws {
        let json = """
        {
          "evidenceID": "corpus-1",
          "kind": "corpus",
          "checkedAt": 0
        }
        """

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                ToolEvidence.self,
                from: Data(json.utf8)
            )
        }
    }

    @Test func encodesCheckedAtAsISO8601() throws {
        let evidence = ToolEvidence(
            evidenceID: "corpus-1",
            kind: .corpus,
            checkedAt: Date(timeIntervalSince1970: 1_781_740_800)
        )

        let data = try JSONEncoder().encode(evidence)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["checkedAt"] as? String == "2026-06-18T00:00:00.000Z")
    }

    @Test func legacyQualificationSummaryDefaultsIndependenceToFalse() throws {
        let json = """
        {
          "qualified": true,
          "observedMetrics": {"passRate": 1.0},
          "observedCounts": {"caseCount": 3},
          "failureCodes": []
        }
        """

        let summary = try JSONDecoder().decode(
            ToolEvidenceQualificationSummary.self,
            from: Data(json.utf8)
        )

        #expect(!summary.independenceVerified)
        #expect(summary.qualificationID == nil)
    }
}
