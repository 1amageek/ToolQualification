import CircuiteFoundation
import Foundation

/// Exact case applicability selected by the independent assessment policy.
public struct ToolQualificationMetricRequirement: Sendable, Hashable, Codable {
    public let caseID: String
    public let metricID: String
    public let inputArtifacts: [ArtifactReference]
    public let phaseIDs: [String]
    public let metricDefinitionArtifact: ArtifactReference
    public let applicability: ToolQualificationAssessmentApplicability
    public let primaryCriterionArtifact: ArtifactReference
    public let oracleCriterionArtifact: ArtifactReference?
    public let agreementCriterionArtifact: ArtifactReference?

    public init(caseID: String, metricID: String, inputArtifacts: [ArtifactReference],
                phaseIDs: [String], metricDefinitionArtifact: ArtifactReference,
                applicability: ToolQualificationAssessmentApplicability,
                primaryCriterionArtifact: ArtifactReference,
                oracleCriterionArtifact: ArtifactReference? = nil,
                agreementCriterionArtifact: ArtifactReference? = nil) {
        self.caseID = caseID
        self.metricID = metricID
        self.inputArtifacts = inputArtifacts.sorted { $0.id.description < $1.id.description }
        self.phaseIDs = phaseIDs.sorted()
        self.metricDefinitionArtifact = metricDefinitionArtifact
        self.applicability = applicability
        self.primaryCriterionArtifact = primaryCriterionArtifact
        self.oracleCriterionArtifact = oracleCriterionArtifact
        self.agreementCriterionArtifact = agreementCriterionArtifact
    }

    public var isStructurallyValid: Bool {
        let links = [metricDefinitionArtifact, primaryCriterionArtifact]
            + [oracleCriterionArtifact, agreementCriterionArtifact].compactMap { $0 }
        let applicable: Bool
        switch applicability {
        case .primaryOnly:
            applicable = oracleCriterionArtifact == nil && agreementCriterionArtifact == nil
        case .primaryAndOracle:
            applicable = oracleCriterionArtifact != nil && agreementCriterionArtifact != nil
        }
        return applicable && [caseID, metricID].allSatisfy(ToolQualificationArtifactValidation.isToken)
            && !inputArtifacts.isEmpty
            && inputArtifacts.allSatisfy(ToolQualificationArtifactValidation.isVerifiable)
            && ToolQualificationArtifactValidation.hasDistinctIdentities(inputArtifacts)
            && inputArtifacts == inputArtifacts.sorted { $0.id.description < $1.id.description }
            && !phaseIDs.isEmpty && phaseIDs.allSatisfy(ToolQualificationArtifactValidation.isToken)
            && Set(phaseIDs).count == phaseIDs.count && phaseIDs == phaseIDs.sorted()
            && links.allSatisfy(ToolQualificationArtifactValidation.isVerifiable)
    }
}
