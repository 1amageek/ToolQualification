import Foundation

public struct ToolProcessQualificationEvidence: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var qualificationID: String
    public var toolID: String
    public var scope: ToolQualificationScope
    public var status: ToolProcessQualificationStatus
    public var corpusEvidenceIDs: [String]
    public var oracleEvidenceIDs: [String]
    public var healthEvidenceIDs: [String]
    public var approvalEvidenceIDs: [String]
    public var evidenceArtifactIDs: [String]
    public var independenceVerified: Bool
    public var blockers: [String]
    public var qualifiedAt: Date?
    public var expiresAt: Date?

    public init(
        qualificationID: String,
        toolID: String,
        scope: ToolQualificationScope,
        status: ToolProcessQualificationStatus = .unqualified,
        corpusEvidenceIDs: [String] = [],
        oracleEvidenceIDs: [String] = [],
        healthEvidenceIDs: [String] = [],
        approvalEvidenceIDs: [String] = [],
        evidenceArtifactIDs: [String] = [],
        independenceVerified: Bool = false,
        blockers: [String] = [],
        qualifiedAt: Date? = nil,
        expiresAt: Date? = nil,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.qualificationID = qualificationID
        self.toolID = toolID
        self.scope = scope
        self.status = status
        self.corpusEvidenceIDs = Self.sortedUnique(corpusEvidenceIDs)
        self.oracleEvidenceIDs = Self.sortedUnique(oracleEvidenceIDs)
        self.healthEvidenceIDs = Self.sortedUnique(healthEvidenceIDs)
        self.approvalEvidenceIDs = Self.sortedUnique(approvalEvidenceIDs)
        self.evidenceArtifactIDs = Self.sortedUnique(evidenceArtifactIDs)
        self.independenceVerified = independenceVerified
        self.blockers = Self.sortedUnique(blockers)
        self.qualifiedAt = qualifiedAt
        self.expiresAt = expiresAt
    }

    public var isStructurallyValid: Bool {
        schemaVersion == Self.currentSchemaVersion
            && !qualificationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !toolID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && scope.isComplete
            && !corpusEvidenceIDs.isEmpty
            && !oracleEvidenceIDs.isEmpty
            && !healthEvidenceIDs.isEmpty
            && !approvalEvidenceIDs.isEmpty
            && !evidenceArtifactIDs.isEmpty
    }

    public func isQualified(at date: Date, requirePDKScope: Bool = false) -> Bool {
        status == .qualified
            && isStructurallyValid
            && (!requirePDKScope || scope.isCompleteForPDK)
            && independenceVerified
            && blockers.isEmpty
            && isFresh(at: date)
    }

    public func isFresh(at date: Date) -> Bool {
        guard let qualifiedAt, let expiresAt else {
            return false
        }
        return qualifiedAt <= date && date < expiresAt
    }

    public func summary(policyID: String? = nil) -> ToolEvidenceQualificationSummary {
        ToolEvidenceQualificationSummary(
            qualified: status == .qualified,
            policyID: policyID,
            observedCounts: [
                "corpusEvidenceCount": corpusEvidenceIDs.count,
                "oracleEvidenceCount": oracleEvidenceIDs.count,
                "healthEvidenceCount": healthEvidenceIDs.count,
                "approvalEvidenceCount": approvalEvidenceIDs.count,
            ],
            failureCodes: blockers,
            scope: scope,
            qualificationID: qualificationID,
            independenceVerified: independenceVerified
        )
    }

    private static func sortedUnique(_ values: [String]) -> [String] {
        Array(Set(values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })).sorted()
    }
}
