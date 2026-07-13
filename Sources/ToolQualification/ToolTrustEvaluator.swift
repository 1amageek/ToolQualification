import Foundation

public struct ToolTrustEvaluator: Sendable {
    public init() {}

    public func evaluate(
        descriptor: ToolDescriptor,
        requirement: ToolTrustRequirement,
        health: ToolHealthCheckResult?,
        evaluatedAt: Date = Date()
    ) -> ToolTrustDecision {
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

        let unqualifiedEvidence = requiredQualifiedEvidenceKinds.filter { kind in
            guard let candidates = evidenceByKind[kind], !candidates.isEmpty else {
                return false
            }
            let freshCandidates = freshEvidence(
                in: candidates,
                maximumAgeSeconds: maximumEvidenceAgeSeconds,
                evaluatedAt: evaluatedAt
            )
            guard !freshCandidates.isEmpty else {
                return false
            }
            return !freshCandidates.contains {
                $0.hasPassingQualificationSupport(
                    requiredScope: requirement.qualificationScope,
                    requireIndependentQualificationEvidence: requirement.requireIndependentQualificationEvidence
                )
            }
        }
        if !unqualifiedEvidence.isEmpty {
            diagnostics.append(ToolDiagnostic(
                severity: .error,
                code: "UNQUALIFIED_REQUIRED_EVIDENCE",
                message: "Tool evidence is present but does not include a passing qualification summary: \(unqualifiedEvidence.map(\.rawValue).sorted().joined(separator: ", "))."
            ))
        }

        return ToolTrustDecision(
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
            [.corpus, .oracle, .productionApproval]
        }
    }
}
