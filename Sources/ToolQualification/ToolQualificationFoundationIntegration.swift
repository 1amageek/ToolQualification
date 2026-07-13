@_exported import CircuiteFoundation
import Foundation

/// Inputs to a trust evaluation that must be reproducible by an engine or CLI.
public struct ToolQualificationRequest: Sendable, Hashable, Codable {
  public let descriptor: ToolDescriptor
  public let requirement: ToolTrustRequirement
  public let health: ToolHealthCheckResult?
  public let inputs: [ArtifactReference]
  public let evaluatedAt: Date

    public init(
      descriptor: ToolDescriptor,
      requirement: ToolTrustRequirement,
      health: ToolHealthCheckResult? = nil,
      inputs: [ArtifactReference] = [],
      evaluatedAt: Date
    ) {
    self.descriptor = descriptor
    self.requirement = requirement
    self.health = health
    self.inputs = inputs
    self.evaluatedAt = evaluatedAt
  }
}

/// Foundation-backed output boundary for trust decisions.
public struct ToolQualificationResult: Sendable, Hashable, Codable, ArtifactProducing,
  DiagnosticReporting, EvidenceProviding
{
  public let decision: ToolTrustDecision
  public let artifacts: [ArtifactReference]
  public let diagnostics: [DesignDiagnostic]
  public let evidence: EvidenceManifest

  public init(
    decision: ToolTrustDecision,
    artifacts: [ArtifactReference] = [],
    diagnostics: [DesignDiagnostic] = [],
    provenance: ExecutionProvenance
  ) {
    self.decision = decision
    self.artifacts = artifacts
    self.diagnostics = diagnostics
    self.evidence = EvidenceManifest(
      provenance: provenance,
      artifacts: artifacts
    )
  }
}

/// Protocol seam for trust evaluators that need to participate in a flow
/// execution while preserving the existing synchronous evaluator API.
public protocol ToolQualificationEngine: Engine
where Request == ToolQualificationRequest, Output == ToolQualificationResult {}
