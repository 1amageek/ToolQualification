# ToolQualification

Tool trust contract for the design harness. A flow's reliability depends on the
tools that process the design, so tools are not just invoked — their capabilities,
versions, verified scope, and failure conditions are captured and gated before a
flow may use them. This package holds the contract only; it never launches a tool
(execution, parsers, and domain validation stay in the engine packages).

## Types

| Type | Responsibility |
|---|---|
| `ToolDescriptor` | Stable tool ID, kind, version, capabilities, trust profile, environment |
| `ToolKind` / `ToolCapability` | Operation IDs and input/output format compatibility |
| `ToolTrustProfile` / `ToolQualificationLevel` | Qualification level (`unknown` → `smokeChecked` → `corpusChecked` → `oracleChecked` → `productionEligible`) plus evidence and known limitations |
| `ToolEvidence` / `ToolEvidenceKind` | Evidence backing a qualification level |
| `ToolHealthCheckResult` / `ToolHealthStatus` | Pass/fail/blocked/notChecked with diagnostics |
| `ToolTrustRequirement` | What a flow stage demands: operation, minimum qualification, formats, health gate |
| `ToolTrustEvaluator` / `ToolTrustDecision` | Eligible/rejected verdict from descriptor + requirement + health |
| `ToolRegistry` | Registers descriptors, selects eligible candidates deterministically |
| `ToolEnvironment` / `ToolAsset` | Executable paths, platform, required assets (PDK, rule decks) |

## Rules

- `unknown` tools are never used for production gates by default.
- A skipped health check is not a pass; flows that require a health gate block
  instead of silently proceeding.

## Build & test

```bash
swift build
swift test
```
