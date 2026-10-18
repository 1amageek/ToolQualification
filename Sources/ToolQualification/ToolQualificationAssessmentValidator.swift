import CircuiteFoundation
import Foundation

/// Reconstructs metric decisions from pinned inputs and original domain outputs.
struct ToolQualificationAssessmentValidator: Sendable {
    let reader: any ToolQualificationArtifactReading

    func validateCorpus(_ result: ToolCorpusQualificationResult,
                        expectedPolicy: ArtifactReference?) async throws {
        let policy = try await loadPolicy(scope: result.scope, expected: expectedPolicy,
                                          inputs: result.inputArtifacts)
        for outcome in result.cases {
            try await validateOutcome(outcome, scope: result.scope, policy: policy,
                inputs: result.inputArtifacts, outputs: result.outputArtifacts, oracle: false)
        }
    }

    func validateOracle(_ result: ToolOracleQualificationResult,
                        expectedPolicy: ArtifactReference?) async throws {
        let policy = try await loadPolicy(scope: result.scope, expected: expectedPolicy,
                                          inputs: result.inputArtifacts)
        for comparison in result.cases {
            try await validateOutcome(comparison.primary, scope: result.scope, policy: policy,
                inputs: result.inputArtifacts, outputs: result.primaryOutputArtifacts, oracle: false)
            try await validateOutcome(comparison.oracle, scope: result.scope, policy: policy,
                inputs: result.inputArtifacts, outputs: result.oracleOutputArtifacts, oracle: true)
            for metric in comparison.agreementComparisons {
                let requirement = try requirement(caseID: comparison.caseID, metricID: metric.metricID, policy: policy)
                guard requirement.applicability == .primaryAndOracle,
                      let reference = requirement.agreementCriterionArtifact,
                      metric.criterionArtifact == reference else {
                    throw failure("oracle agreement is not applicable or is not bound to its policy criterion")
                }
                let criterion = try await loadCriterion(reference, requirement: requirement, inputs: result.inputArtifacts)
                guard criterion.referenceValue == nil,
                      let tolerance = criterion.comparisonRule.absoluteTolerance(reference: metric.oracleObserved),
                      tolerance == metric.absoluteTolerance, metric.passed else {
                    throw failure("oracle agreement differs from its independent criterion")
                }
            }
        }
    }

    func validateCoverage(caseIDs: Set<String>, scope: ToolQualificationScope,
                          inputs: [ArtifactReference]) async throws {
        let policy = try await loadPolicy(scope: scope, expected: scope.assessmentPolicyArtifact, inputs: inputs)
        guard Set(policy.requirements.map(\.caseID)) == caseIDs,
              policy.requirements.allSatisfy({ $0.applicability == .primaryAndOracle }) else {
            throw failure("process qualification requires all independently specified oracle cases")
        }
    }

    private func validateOutcome(_ outcome: ToolQualificationCaseOutcome, scope: ToolQualificationScope,
                                 policy: ToolQualificationAssessmentPolicy, inputs: [ArtifactReference],
                                 outputs: [ArtifactReference], oracle: Bool) async throws {
        guard outputs.contains(outcome.originalExecutionArtifact) else {
            throw failure("original execution is not retained by the result")
        }
        let execution = try ToolQualificationCaseExecution.decodeCanonical(
            from: await reader.verifiedData(for: outcome.originalExecutionArtifact))
        let implementation = oracle ? scope.oracle?.implementationID : scope.implementationID
        let version = oracle ? scope.oracle?.version : scope.toolVersion
        let binary = oracle ? scope.oracle?.binaryDigest : scope.binaryDigest
        guard execution.caseID == outcome.caseID,
              execution.producer.identifier == implementation, execution.producer.version == version,
              execution.executableArtifact.digest.hexadecimalValue == binary,
              Set(execution.inputArtifacts).isSubset(of: Set(inputs)),
              execution.observedMetrics == Dictionary(uniqueKeysWithValues:
                outcome.comparisons.map { ($0.metricID, $0.observed) }),
              Set(policy.requirements.filter { $0.caseID == outcome.caseID }.map(\.metricID))
                == Set(execution.observedMetrics.keys) else {
            throw failure("original execution identity, observations or policy metric inventory differs")
        }
        _ = try await reader.verifiedData(for: execution.executableArtifact)
        guard Set(execution.modelReceiptArtifacts).isSubset(of: Set(outputs)) else {
            throw failure("original model receipts are not retained by the result")
        }
        var consumedByPhaseAndModel: [String: Set<String>] = [:]
        for reference in execution.modelReceiptArtifacts {
            let receipt = try ToolQualificationModelExecutionReceipt.decodeCanonical(
                from: await reader.verifiedData(for: reference))
            let identity = receipt.phaseID + "\u{0}" + receipt.modelID
            guard receipt.caseID == execution.caseID, receipt.executionID == execution.executionID,
                  receipt.producer == execution.producer, receipt.inputArtifacts == execution.inputArtifacts,
                  execution.phaseIDs.contains(receipt.phaseID),
                  Set(receipt.consumedInstances.keys).isDisjoint(with: consumedByPhaseAndModel[identity] ?? []) else {
                throw failure("original model receipt binding or phase consumption is inconsistent")
            }
            consumedByPhaseAndModel[identity, default: []].formUnion(receipt.consumedInstances.keys)
        }
        for metric in outcome.comparisons {
            let requirement = try requirement(caseID: outcome.caseID, metricID: metric.metricID, policy: policy)
            guard execution.metricDefinitionArtifacts[metric.metricID] == requirement.metricDefinitionArtifact,
                  execution.metricPhaseIDs[metric.metricID] == requirement.phaseIDs,
                  Set(execution.inputArtifacts) == Set(requirement.inputArtifacts) else {
                throw failure("original metric definition, contributing phases or exact inputs differ from policy")
            }
            let reference: ArtifactReference
            if oracle {
                guard requirement.applicability == .primaryAndOracle,
                      let oracleReference = requirement.oracleCriterionArtifact else {
                    throw failure("oracle observation is not applicable to this independent policy")
                }
                reference = oracleReference
            } else { reference = requirement.primaryCriterionArtifact }
            guard metric.criterionArtifact == reference else {
                throw failure("outcome criterion differs from the independently pinned policy")
            }
            let criterion = try await loadCriterion(reference, requirement: requirement, inputs: inputs)
            guard let expected = criterion.referenceValue,
                  let tolerance = criterion.comparisonRule.absoluteTolerance(reference: expected),
                  expected == metric.expected, tolerance == metric.absoluteTolerance, metric.passed else {
                throw failure("outcome expected value, tolerance or verdict differs from its independent criterion")
            }
        }
    }

    private func loadPolicy(scope: ToolQualificationScope, expected: ArtifactReference?,
                            inputs: [ArtifactReference]) async throws -> ToolQualificationAssessmentPolicy {
        guard let expected, scope.assessmentPolicyArtifact == expected, inputs.contains(expected) else {
            throw failure("metric assessment requires an independent pinned policy retained as an input")
        }
        let policy = try ToolQualificationAssessmentPolicy.decodeCanonical(from: await reader.verifiedData(for: expected))
        for requirement in policy.requirements {
            guard Set(requirement.inputArtifacts).isSubset(of: Set(inputs)) else {
                throw failure("policy case inputs are not retained")
            }
            for input in requirement.inputArtifacts { _ = try await reader.verifiedData(for: input) }
        }
        return policy
    }

    private func loadCriterion(_ reference: ArtifactReference, requirement: ToolQualificationMetricRequirement,
                               inputs: [ArtifactReference]) async throws -> ToolQualificationMetricCriterion {
        guard inputs.contains(reference), inputs.contains(requirement.metricDefinitionArtifact) else {
            throw failure("criterion or metric definition is not retained as an input")
        }
        let definition = try ToolQualificationMetricDefinition.decodeCanonical(
            from: await reader.verifiedData(for: requirement.metricDefinitionArtifact))
        let criterion = try ToolQualificationMetricCriterion.decodeCanonical(from: await reader.verifiedData(for: reference))
        guard definition.metricID == requirement.metricID,
              criterion.metricDefinitionArtifact == requirement.metricDefinitionArtifact,
              inputs.contains(definition.domainArtifact), inputs.contains(criterion.requirementArtifact),
              Set(criterion.referenceArtifacts).isSubset(of: Set(inputs)) else {
            throw failure("criterion source, definition or reference inventory does not match the policy")
        }
        for source in [definition.domainArtifact, criterion.requirementArtifact] + criterion.referenceArtifacts {
            _ = try await reader.verifiedData(for: source)
        }
        return criterion
    }

    private func requirement(caseID: String, metricID: String,
                             policy: ToolQualificationAssessmentPolicy) throws -> ToolQualificationMetricRequirement {
        guard let requirement = policy.requirements.first(where: { $0.caseID == caseID && $0.metricID == metricID }) else {
            throw failure("case metric is absent from the independently pinned policy")
        }
        return requirement
    }

    private func failure(_ message: String) -> ToolProcessQualificationEvidenceBuildError {
        .invalidInput(message)
    }
}
