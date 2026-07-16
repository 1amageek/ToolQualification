import Foundation
import CircuiteFoundation

public struct ToolTrustEvaluator: ToolTrustEvaluating, Sendable {
    private let processEvidenceValidator: any ToolProcessQualificationEvidenceValidating

    public init(
        processEvidenceValidator: any ToolProcessQualificationEvidenceValidating = ToolProcessQualificationEvidenceValidator()
    ) {
        self.processEvidenceValidator = processEvidenceValidator
    }

    public func evaluate(
        descriptor: ToolDescriptor,
        requirement: ToolTrustRequirement,
        health: ToolHealthCheckResult?,
        artifactReader: (any ToolQualificationArtifactReading)? = nil,
        evaluatedAt: Date = Date()
    ) async -> ToolTrustDecision {
        var diagnostics: [ToolDiagnostic] = []

        if descriptor.kind != requirement.kind {
            diagnostics.append(ToolDiagnostic(
                severity: .error,
                code: "TOOL_KIND_MISMATCH",
                message: "Tool kind does not match the requested operation kind."
            ))
        }

        if descriptor.trustProfile.level < requirement.minimumLevel {
            diagnostics.append(ToolDiagnostic(
                severity: .error,
                code: "INSUFFICIENT_TRUST_LEVEL",
                message: "Tool qualification level is below the required minimum."
            ))
        }

        let capability = descriptor.capabilities.first { $0.operationID == requirement.operationID }
        if capability == nil {
            diagnostics.append(ToolDiagnostic(
                severity: .error,
                code: "MISSING_CAPABILITY",
                message: "Tool does not declare the requested operation capability."
            ))
        }

        if let capability {
            let inputFormats = Set(capability.inputFormats)
            let missingInputs = requirement.requiredInputFormats.filter { !inputFormats.contains($0) }
            if !missingInputs.isEmpty {
                diagnostics.append(ToolDiagnostic(
                    severity: .error,
                    code: "MISSING_INPUT_FORMAT",
                    message: "Tool does not support all required input formats."
                ))
            }

            let outputFormats = Set(capability.outputFormats)
            let missingOutputs = requirement.requiredOutputFormats.filter { !outputFormats.contains($0) }
            if !missingOutputs.isEmpty {
                diagnostics.append(ToolDiagnostic(
                    severity: .error,
                    code: "MISSING_OUTPUT_FORMAT",
                    message: "Tool does not support all required output formats."
                ))
            }
        }

        let applicableHealth: ToolHealthCheckResult?
        if let health, health.toolID != descriptor.toolID {
            diagnostics.append(ToolDiagnostic(
                severity: .error,
                code: "HEALTH_CHECK_TOOL_ID_MISMATCH",
                message: "Tool health check result belongs to \(health.toolID), not \(descriptor.toolID)."
            ))
            applicableHealth = nil
        } else {
            applicableHealth = health
        }

        if requirement.requirePassingHealthCheck {
            switch applicableHealth?.status {
            case .passed:
                break
            case .failed:
                diagnostics.append(ToolDiagnostic(
                    severity: .error,
                    code: "HEALTH_CHECK_FAILED",
                    message: "Tool health check failed."
                ))
            case .blocked:
                diagnostics.append(ToolDiagnostic(
                    severity: .error,
                    code: "HEALTH_CHECK_BLOCKED",
                    message: "Tool health check is blocked."
                ))
            case .notChecked, .none:
                diagnostics.append(ToolDiagnostic(
                    severity: .error,
                    code: "HEALTH_CHECK_REQUIRED",
                    message: "Tool requires a passing health check before selection."
                ))
            }
        }

        let evidence = descriptor.trustProfile.evidence + (applicableHealth?.evidence ?? [])
        let evidenceByKind = Dictionary(grouping: evidence, by: \.kind)
        let requiredQualifiedEvidenceKinds = Set(
            requirement.requiredQualifiedEvidenceKinds
                + Self.impliedQualifiedEvidenceKinds(for: requirement.minimumLevel)
                + Self.impliedQualifiedEvidenceKinds(for: descriptor.trustProfile.level)
        )
        let requiredEvidenceKinds = Set(requirement.requiredEvidenceKinds)
            .union(requiredQualifiedEvidenceKinds)
        let missingEvidence = requiredEvidenceKinds.filter { evidenceByKind[$0]?.isEmpty ?? true }
        if !missingEvidence.isEmpty {
            diagnostics.append(ToolDiagnostic(
                severity: .error,
                code: "MISSING_REQUIRED_EVIDENCE",
                message: "Tool evidence is missing required qualification evidence: \(missingEvidence.map(\.rawValue).sorted().joined(separator: ", "))."
            ))
        }

        let maximumEvidenceAgeSeconds = requirement.maximumEvidenceAgeSeconds
        if let maximumEvidenceAgeSeconds,
           maximumEvidenceAgeSeconds <= 0 || !maximumEvidenceAgeSeconds.isFinite {
            diagnostics.append(ToolDiagnostic(
                severity: .error,
                code: "INVALID_EVIDENCE_FRESHNESS_REQUIREMENT",
                message: "maximumEvidenceAgeSeconds must be a finite value greater than zero."
            ))
        }

        let staleEvidence = requiredEvidenceKinds.filter { kind in
            guard let candidates = evidenceByKind[kind], !candidates.isEmpty else {
                return false
            }
            return freshEvidence(
                in: candidates,
                maximumAgeSeconds: maximumEvidenceAgeSeconds,
                evaluatedAt: evaluatedAt
            ).isEmpty
        }
        if !staleEvidence.isEmpty {
            var message = "Tool evidence is present but missing a fresh checkedAt timestamp or exceeds maximumEvidenceAgeSeconds: \(staleEvidence.map(\.rawValue).sorted().joined(separator: ", "))."
            let futureCheckedAtDetails = futureCheckedAtDetails(
                for: staleEvidence,
                evidenceByKind: evidenceByKind,
                evaluatedAt: evaluatedAt
            )
            if !futureCheckedAtDetails.isEmpty {
                message += " checkedAt is in the future for: \(futureCheckedAtDetails.joined(separator: ", "))."
            }
            diagnostics.append(ToolDiagnostic(
                severity: .error,
                code: "STALE_REQUIRED_EVIDENCE",
                message: message
            ))
        }

        var unqualifiedEvidence = Set<ToolEvidenceKind>()
        for kind in requiredQualifiedEvidenceKinds {
            guard let candidates = evidenceByKind[kind], !candidates.isEmpty else { continue }
            let freshCandidates = freshEvidence(
                in: candidates,
                maximumAgeSeconds: maximumEvidenceAgeSeconds,
                evaluatedAt: evaluatedAt
            )
            guard !freshCandidates.isEmpty, let artifactReader else {
                unqualifiedEvidence.insert(kind)
                continue
            }
            var hasPassingResult = false
            for evidence in freshCandidates where !hasPassingResult {
                if let failure = await evidenceFailure(
                    evidence,
                    toolID: descriptor.toolID,
                    requiredScope: requirement.qualificationScope,
                    requireIndependentOracle: requirement.requireIndependentQualificationEvidence,
                    reading: artifactReader
                ) {
                    diagnostics.append(failure)
                } else {
                    hasPassingResult = true
                }
            }
            if !hasPassingResult { unqualifiedEvidence.insert(kind) }
        }
        if !unqualifiedEvidence.isEmpty {
            diagnostics.append(ToolDiagnostic(
                severity: .error,
                code: "UNQUALIFIED_REQUIRED_EVIDENCE",
                message: "Tool evidence is present but its retained raw result does not derive a passing qualification: \(unqualifiedEvidence.map(\.rawValue).sorted().joined(separator: ", "))."
            ))
        }

        if descriptor.trustProfile.level == .productionEligible
            || requirement.minimumLevel == .productionEligible {
            guard let processQualification = descriptor.trustProfile.processQualification else {
                diagnostics.append(ToolDiagnostic(
                    severity: .error,
                    code: "PRODUCTION_QUALIFICATION_REQUIRED",
                    message: "Production eligibility requires a retained process qualification record."
                ))
                return decision(descriptor: descriptor, diagnostics: diagnostics)
            }
            if processQualification.toolID != descriptor.toolID
                || processQualification.scope.implementationID != descriptor.toolID
                || processQualification.scope.toolVersion != descriptor.version {
                diagnostics.append(ToolDiagnostic(
                    severity: .error,
                    code: "PRODUCTION_TOOL_IDENTITY_MISMATCH",
                    message: "Process qualification must bind the exact tool identifier and version."
                ))
            }
            if let requiredScope = requirement.qualificationScope,
               processQualification.scope != requiredScope {
                diagnostics.append(ToolDiagnostic(
                    severity: .error,
                    code: "PRODUCTION_SCOPE_MISMATCH",
                    message: "Process qualification scope does not match the requested binary, process, PDK, deck, and oracle scope."
                ))
            }
            if !processQualification.isQualified(at: evaluatedAt, requirePDKScope: true) {
                diagnostics.append(ToolDiagnostic(
                    severity: .error,
                    code: "PRODUCTION_QUALIFICATION_INVALID",
                    message: "Process qualification is incomplete, expired, lacks independent oracle scope, or lacks retained input/output artifacts."
                ))
            }
            if let artifactReader {
                do {
                    try await processEvidenceValidator.validate(
                        processQualification,
                        reading: artifactReader,
                        at: evaluatedAt
                    )
                } catch {
                    diagnostics.append(ToolDiagnostic(
                        severity: .error,
                        code: "PRODUCTION_QUALIFICATION_DERIVATION_FAILED",
                        message: "Production qualification artifacts failed integrity verification or could not reproduce the retained corpus, oracle, and health results: \(error.localizedDescription)"
                    ))
                }
            } else {
                diagnostics.append(ToolDiagnostic(
                    severity: .error,
                    code: "PRODUCTION_ARTIFACT_READER_REQUIRED",
                    message: "Production eligibility requires a verified qualification artifact reader."
                ))
            }
        }

        return decision(descriptor: descriptor, diagnostics: diagnostics)
    }

    private func decision(
        descriptor: ToolDescriptor,
        diagnostics: [ToolDiagnostic]
    ) -> ToolTrustDecision {
        ToolTrustDecision(
            toolID: descriptor.toolID,
            status: diagnostics.contains { $0.severity == .error } ? .rejected : .eligible,
            diagnostics: diagnostics + descriptor.trustProfile.knownLimitations.map {
                ToolDiagnostic(severity: .warning, code: "KNOWN_LIMITATION", message: $0)
            }
        )
    }

    /// Describes, per stale evidence kind, the checkedAt timestamps that lie
    /// in the future relative to `evaluatedAt`. A future timestamp fails the
    /// freshness gate just like a stale one, but the diagnostic must say so
    /// explicitly instead of claiming the timestamp is missing or too old.
    private func futureCheckedAtDetails(
        for staleKinds: Set<ToolEvidenceKind>,
        evidenceByKind: [ToolEvidenceKind: [ToolEvidence]],
        evaluatedAt: Date
    ) -> [String] {
        let formatter = ISO8601DateFormatter()
        return staleKinds
            .compactMap { kind -> (kind: String, checkedAt: Date)? in
                let futureDates = (evidenceByKind[kind] ?? []).compactMap { evidence -> Date? in
                    guard let checkedAt = evidence.checkedAt, checkedAt > evaluatedAt else {
                        return nil
                    }
                    return checkedAt
                }
                guard let latest = futureDates.max() else {
                    return nil
                }
                return (kind.rawValue, latest)
            }
            .sorted { $0.kind < $1.kind }
            .map { "\($0.kind) (\(formatter.string(from: $0.checkedAt)))" }
    }

    private func freshEvidence(
        in candidates: [ToolEvidence],
        maximumAgeSeconds: TimeInterval?,
        evaluatedAt: Date
    ) -> [ToolEvidence] {
        guard let maximumAgeSeconds,
              maximumAgeSeconds > 0,
              maximumAgeSeconds.isFinite else {
            return candidates
        }
        return candidates.filter { evidence in
            guard let checkedAt = evidence.checkedAt else {
                return false
            }
            let age = evaluatedAt.timeIntervalSince(checkedAt)
            return age >= 0 && age <= maximumAgeSeconds
        }
    }

    private func evidenceFailure(
        _ evidence: ToolEvidence,
        toolID: String,
        requiredScope: ToolQualificationScope?,
        requireIndependentOracle: Bool,
        reading artifacts: any ToolQualificationArtifactReading
    ) async -> ToolDiagnostic? {
        guard let artifact = evidence.artifact else {
            return evidenceDiagnostic(
                evidence,
                code: "QUALIFICATION_EVIDENCE_ARTIFACT_MISSING",
                detail: "does not retain an artifact reference"
            )
        }
        let data: Data
        do {
            data = try await artifacts.verifiedData(for: artifact)
        } catch {
            return evidenceDiagnostic(
                evidence,
                code: "QUALIFICATION_EVIDENCE_INTEGRITY_FAILED",
                detail: error.localizedDescription
            )
        }
        do {
            switch evidence.kind {
            case .smoke:
                let result = try ToolSmokeQualificationResult.decodeCanonical(from: data)
                guard result.toolID == toolID,
                      result.issuer.kind == .engine,
                      artifact.producer == result.issuer else {
                    return evidenceDiagnostic(evidence, code: "QUALIFICATION_EVIDENCE_IDENTITY_MISMATCH", detail: "smoke result identity or issuer does not match")
                }
                guard result.checkedAt == evidence.checkedAt else {
                    return evidenceDiagnostic(evidence, code: "QUALIFICATION_EVIDENCE_TIME_MISMATCH", detail: "smoke checkedAt does not match")
                }
                guard result.isPassing else {
                    return evidenceDiagnostic(evidence, code: "QUALIFICATION_EVIDENCE_SMOKE_FAILED", detail: "smoke diagnostics contain an error")
                }
            case .corpus:
                let result = try ToolCorpusQualificationResult.decodeCanonical(from: data)
                guard result.toolID == toolID,
                      result.issuer.kind == .engine,
                      artifact.producer == result.issuer else {
                    return evidenceDiagnostic(evidence, code: "QUALIFICATION_EVIDENCE_IDENTITY_MISMATCH", detail: "corpus result identity or issuer does not match")
                }
                guard result.checkedAt == evidence.checkedAt else {
                    return evidenceDiagnostic(evidence, code: "QUALIFICATION_EVIDENCE_TIME_MISMATCH", detail: "corpus checkedAt does not match")
                }
                guard requiredScope.map({ result.scope == $0 }) ?? true,
                      !requireIndependentOracle || result.scope.isCompleteForProduction else {
                    return evidenceDiagnostic(evidence, code: "QUALIFICATION_EVIDENCE_SCOPE_MISMATCH", detail: "corpus scope does not match")
                }
                guard result.isPassing else {
                    return evidenceDiagnostic(evidence, code: "QUALIFICATION_EVIDENCE_CASE_MISMATCH", detail: "corpus findings do not derive a passing result")
                }
            case .oracle:
                let result = try ToolOracleQualificationResult.decodeCanonical(from: data)
                guard result.primaryToolID == toolID,
                      result.issuer.kind == .engine,
                      artifact.producer == result.issuer else {
                    return evidenceDiagnostic(evidence, code: "QUALIFICATION_EVIDENCE_IDENTITY_MISMATCH", detail: "oracle result identity or issuer does not match")
                }
                guard result.checkedAt == evidence.checkedAt else {
                    return evidenceDiagnostic(evidence, code: "QUALIFICATION_EVIDENCE_TIME_MISMATCH", detail: "oracle checkedAt does not match")
                }
                guard requiredScope.map({ result.scope == $0 }) ?? true,
                      !requireIndependentOracle || result.scope.isCompleteForProduction else {
                    return evidenceDiagnostic(evidence, code: "QUALIFICATION_EVIDENCE_SCOPE_MISMATCH", detail: "oracle scope does not match")
                }
                guard result.isPassing else {
                    return evidenceDiagnostic(evidence, code: "QUALIFICATION_EVIDENCE_CASE_MISMATCH", detail: "oracle findings do not derive passing agreement")
                }
            case .healthCheck:
                let result = try ToolHealthQualificationResult.decodeCanonical(from: data)
                guard result.toolID == toolID,
                      result.issuer.kind == .engine,
                      artifact.producer == result.issuer else {
                    return evidenceDiagnostic(evidence, code: "QUALIFICATION_EVIDENCE_IDENTITY_MISMATCH", detail: "health result identity or issuer does not match")
                }
                guard result.checkedAt == evidence.checkedAt else {
                    return evidenceDiagnostic(evidence, code: "QUALIFICATION_EVIDENCE_TIME_MISMATCH", detail: "health checkedAt does not match")
                }
                guard requiredScope.map({ result.scope == $0 }) ?? true,
                      !requireIndependentOracle || result.scope.isCompleteForProduction else {
                    return evidenceDiagnostic(evidence, code: "QUALIFICATION_EVIDENCE_SCOPE_MISMATCH", detail: "health scope does not match")
                }
                guard result.isPassing else {
                    return evidenceDiagnostic(evidence, code: "QUALIFICATION_EVIDENCE_HEALTH_FAILED", detail: "health diagnostics contain an error")
                }
            }
            return nil
        } catch {
            return evidenceDiagnostic(
                evidence,
                code: "QUALIFICATION_EVIDENCE_NONCANONICAL",
                detail: error.localizedDescription
            )
        }
    }

    private func evidenceDiagnostic(
        _ evidence: ToolEvidence,
        code: String,
        detail: String
    ) -> ToolDiagnostic {
        ToolDiagnostic(
            severity: .error,
            code: code,
            message: "Evidence \(evidence.evidenceID) (\(evidence.kind.rawValue)) \(detail)."
        )
    }

    private static func impliedQualifiedEvidenceKinds(
        for level: ToolQualificationLevel
    ) -> [ToolEvidenceKind] {
        switch level {
        case .unknown:
            []
        case .smokeChecked:
            [.smoke]
        case .corpusChecked:
            [.corpus]
        case .oracleChecked:
            [.corpus, .oracle]
        case .productionEligible:
            [.corpus, .oracle, .healthCheck]
        }
    }
}
