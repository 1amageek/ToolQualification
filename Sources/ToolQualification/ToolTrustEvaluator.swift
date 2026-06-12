import Foundation

public struct ToolTrustEvaluator: Sendable {
    public init() {}

    public func evaluate(
        descriptor: ToolDescriptor,
        requirement: ToolTrustRequirement,
        health: ToolHealthCheckResult?
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

        if requirement.requirePassingHealthCheck {
            switch health?.status {
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

        return ToolTrustDecision(
            toolID: descriptor.toolID,
            status: diagnostics.contains { $0.severity == .error } ? .rejected : .eligible,
            diagnostics: diagnostics + descriptor.trustProfile.knownLimitations.map {
                ToolDiagnostic(severity: .warning, code: "KNOWN_LIMITATION", message: $0)
            }
        )
    }
}
