import CircuiteFoundation
import CircuiteFoundationCrypto
import Foundation
import ToolQualification

/// Independent test policy created before original execution outputs.
struct AssessmentFixture {
    let policy: ArtifactReference
    let definition: ArtifactReference
    let primaryCriterion: ArtifactReference
    let agreementCriterion: ArtifactReference?
    let inputs: [ArtifactReference]
    let dataByReference: [ArtifactReference: Data]
    let paths: [ArtifactReference: URL]

    init(root: URL, caseID: String, metricID: String, originalInputs: [ArtifactReference],
         phases: [String] = ["analysis"], oracle: Bool = true, writeToDisk: Bool = true) throws {
        var dataMap: [ArtifactReference: Data] = [:]
        var pathMap: [ArtifactReference: URL] = [:]
        func store(_ name: String, _ data: Data) throws -> ArtifactReference {
            let url = root.appending(path: "assessment/" + name + ".json")
            if writeToDisk {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            }
            let reference = try ArtifactReference(digest: SHA256ContentDigester().digest(data: data),
                byteCount: UInt64(data.count), descriptor: ArtifactDescriptor(role: .input, kind: .input, format: .json))
            dataMap[reference] = data; pathMap[reference] = url
            return reference
        }
        let source = try store("requirement", Data("independent zero-error requirement".utf8))
        definition = try store("definition", ToolQualificationMetricDefinition(metricID: metricID,
            unitID: "count", extractionID: "fixture-observation-v1", domainArtifact: originalInputs[0]).canonicalData())
        primaryCriterion = try store("primary-criterion", ToolQualificationMetricCriterion(purpose: .circuitRequirement,
            metricDefinitionArtifact: definition, requirementArtifact: source, referenceValue: 0,
            comparisonRule: .absolute(maximumError: 0)).canonicalData())
        agreementCriterion = oracle ? try store("agreement-criterion", ToolQualificationMetricCriterion(
            purpose: .implementationCorrelation, metricDefinitionArtifact: definition,
            requirementArtifact: source, referenceValue: nil, comparisonRule: .absolute(maximumError: 0)).canonicalData()) : nil
        policy = try store("policy", ToolQualificationAssessmentPolicy(policyID: "independent-test-policy",
            requirements: [ToolQualificationMetricRequirement(caseID: caseID, metricID: metricID,
                inputArtifacts: originalInputs, phaseIDs: phases, metricDefinitionArtifact: definition,
                applicability: oracle ? .primaryAndOracle : .primaryOnly, primaryCriterionArtifact: primaryCriterion,
                oracleCriterionArtifact: oracle ? primaryCriterion : nil,
                agreementCriterionArtifact: agreementCriterion)]).canonicalData())
        inputs = Array(dataMap.keys).sorted { $0.id.description < $1.id.description }
        dataByReference = dataMap; paths = pathMap
    }
}
