import CircuiteFoundation
import CircuiteFoundationCrypto
import Foundation
import Testing
@testable import ToolQualification

@Suite("Independent retained assessment policy")
struct ToolQualificationAssessmentPolicyTests {
    @Test("primary-only applicability preserves absent oracle and physical references")
    func primaryOnlyApplicability() throws {
        let input = try reference(Data("case-input".utf8))
        let fixture = try AssessmentFixture(root: FileManager.default.temporaryDirectory,
            caseID: "case", metricID: "metric", originalInputs: [input], oracle: false, writeToDisk: false)
        let policy = try ToolQualificationAssessmentPolicy.decodeCanonical(
            from: #require(fixture.dataByReference[fixture.policy]))
        let requirement = try #require(policy.requirements.first)
        #expect(requirement.applicability == .primaryOnly)
        #expect(requirement.oracleCriterionArtifact == nil)
        #expect(requirement.agreementCriterionArtifact == nil)
        let criterion = try ToolQualificationMetricCriterion.decodeCanonical(
            from: #require(fixture.dataByReference[fixture.primaryCriterion]))
        #expect(criterion.purpose == .circuitRequirement)
        #expect(criterion.referenceArtifacts.isEmpty)
    }

    @Test("declared oracle applicability requires both oracle and agreement links")
    func refusesMissingApplicableLinks() throws {
        let input = try reference(Data("case-input".utf8))
        let fixture = try AssessmentFixture(root: FileManager.default.temporaryDirectory,
            caseID: "case", metricID: "metric", originalInputs: [input], oracle: false, writeToDisk: false)
        for applicability in [ToolQualificationAssessmentApplicability.primaryOnly, .primaryAndOracle] {
            let requirement = ToolQualificationMetricRequirement(caseID: "case", metricID: "metric",
                inputArtifacts: [input], phaseIDs: ["analysis"], metricDefinitionArtifact: fixture.definition,
                applicability: applicability, primaryCriterionArtifact: fixture.primaryCriterion,
                oracleCriterionArtifact: applicability == .primaryOnly ? fixture.primaryCriterion : nil)
            #expect(!requirement.isStructurallyValid)
            #expect(throws: ToolProcessQualificationEvidenceBuildError.self) {
                _ = try ToolQualificationAssessmentPolicy(policyID: "invalid", requirements: [requirement]).canonicalData()
            }
        }
    }

    @Test("physical validation requires explicit immutable reference sources")
    func refusesMissingPhysicalReference() throws {
        let input = try reference(Data("case-input".utf8))
        let criterion = ToolQualificationMetricCriterion(purpose: .physicalModelValidation,
            metricDefinitionArtifact: input, requirementArtifact: input, referenceValue: 0,
            comparisonRule: .absolute(maximumError: 0))
        #expect(throws: ToolProcessQualificationEvidenceBuildError.self) { _ = try criterion.canonicalData() }
    }

    @Test("decoded policy phases preserve strict canonical ordering")
    func refusesNoncanonicalPhaseOrdering() throws {
        let input = try reference(Data("case-input".utf8))
        let fixture = try AssessmentFixture(root: FileManager.default.temporaryDirectory,
            caseID: "case", metricID: "metric", originalInputs: [input], phases: ["first", "second"],
            oracle: false, writeToDisk: false)
        let data = try #require(fixture.dataByReference[fixture.policy])
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var requirements = try #require(object["requirements"] as? [[String: Any]])
        requirements[0]["phaseIDs"] = ["second", "first"]
        object["requirements"] = requirements
        let encoded = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        #expect(throws: ToolProcessQualificationEvidenceBuildError.self) {
            _ = try ToolQualificationAssessmentPolicy.decodeCanonical(from: encoded)
        }
    }

    @Test("combined error preserves near-zero floor and refuses overflowing bounds")
    func combinedErrorRule() {
        let rule = ToolQualificationComparisonRule.combined(absoluteFloor: 0.001, maximumRelativeError: 0.01)
        #expect(rule.absoluteTolerance(reference: 0) == 0.001)
        #expect(rule.absoluteTolerance(reference: -10) == 0.101)
        #expect(ToolQualificationComparisonRule.combined(absoluteFloor: .greatestFiniteMagnitude,
            maximumRelativeError: .greatestFiniteMagnitude).absoluteTolerance(reference: 2) == nil)
        #expect(ToolQualificationComparisonRule.absolute(maximumError: -1).absoluteTolerance(reference: 0) == nil)
        #expect(rule.absoluteTolerance(reference: .infinity) == nil)
    }

    private func reference(_ data: Data) throws -> ArtifactReference {
        try ArtifactReference(digest: SHA256ContentDigester().digest(data: data), byteCount: UInt64(data.count),
            descriptor: ArtifactDescriptor(role: .input, kind: .input, format: .json))
    }
}
