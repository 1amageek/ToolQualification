# ToolQualification Requirements

## Required capabilities

| ID | Requirement |
|---|---|
| TQ-001 | Build independently with local `CircuiteFoundation`; do not depend on Xcircuite or a project persistence package. |
| TQ-002 | Expose `ToolQualificationEngine` as the Foundation engine boundary. |
| TQ-003 | Keep qualification requests/results `Sendable`, `Hashable`, and `Codable`. |
| TQ-004 | Preserve the existing evaluator's fail-closed checks for kind, capability, format, health, evidence, freshness, scope, and independence. |
| TQ-005 | Require evidence summaries and artifact references to be explicit; do not invent digests or approval records. |
| TQ-006 | Keep registry selection deterministic and rank eligible candidates consistently. |
| TQ-007 | Keep process qualification records reproducible, timestamped, scoped, and independently reviewable. |
| TQ-008 | Keep the CLI headless, machine-readable, and stable for Agent use with typed command results and structured diagnostics. |
| TQ-009 | Keep qualification records portable; project/run migration and persistence belong to Xcircuite and DesignFlowKernel. |

## Quality and acceptance criteria

- `swift build` succeeds in the package checkout.
- The current regression baseline remains green: 58 tests pass under a bounded
  `swift test` run.
- An unknown, stale, unqualified, unhealthy, or scope-mismatched tool is never
  eligible by default.
- Missing or malformed evidence produces typed diagnostics and a rejected or
  blocked result rather than a warning-only pass.
- CLI results and failures remain JSON-serializable and reproducible from the
  same input files and evaluation time.

## Non-goals

- No external process execution or tool installation.
- No domain-specific corpus runner or foundry qualification claim.
- No project/run lifecycle, approval ledger, or flow scheduling.
- No project/run persistence, `.xcircuite` filesystem handling, or flow resume.

## Next-agent acceptance gate

An implementation agent is complete when a concrete `ToolQualificationEngine`
can evaluate a request through the existing trust evaluator, return a
Foundation-backed result with preserved diagnostics and provenance, and pass
the build, regression, CLI, and fail-closed checks above.
