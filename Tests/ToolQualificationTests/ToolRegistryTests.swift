import CircuiteFoundation
import Foundation
import Testing
import ToolQualification

@Suite("Tool registry")
struct ToolRegistryTests {
    @Test func upsertReplacesDescriptorByToolID() throws {
        var registry = try ToolRegistry(descriptors: [
            makeDescriptor(toolID: "drc", level: .unknown),
        ])

        try registry.upsert(makeDescriptor(toolID: "drc", level: .smokeChecked))

        #expect(registry.descriptor(toolID: "drc")?.trustProfile.level == .smokeChecked)
    }

    @Test func upsertRejectsInvalidToolID() {
        var registry = ToolRegistry()

        #expect(throws: ToolQualificationError.invalidToolID("../drc")) {
            try registry.upsert(makeDescriptor(toolID: "../drc", level: .unknown))
        }
    }

    @Test func deterministicTieBreakUsesToolID() async throws {
        let qualification = try SmokeQualificationFixture()
        let registry = try ToolRegistry(descriptors: [
            try await qualification.descriptor(toolID: "z-tool"),
            try await qualification.descriptor(toolID: "a-tool"),
        ])
        let health = [
            "a-tool": ToolHealthCheckResult(toolID: "a-tool", status: .passed),
            "z-tool": ToolHealthCheckResult(toolID: "z-tool", status: .passed),
        ]

        let selected = await registry.select(
            requirement: makeRequirement(),
            healthResults: health,
            artifactReader: qualification.reader
        )

        #expect(selected?.toolID == "a-tool")
    }

    @Test func selectPrefersTheMostQualifiedEligibleCandidate() async throws {
        let qualification = try SmokeQualificationFixture()
        let registry = try ToolRegistry(descriptors: [
            makeDescriptor(toolID: "unknown-tool", level: .unknown),
            try await qualification.descriptor(toolID: "smoke-tool"),
        ])
        let health = [
            "unknown-tool": ToolHealthCheckResult(toolID: "unknown-tool", status: .passed),
            "smoke-tool": ToolHealthCheckResult(toolID: "smoke-tool", status: .passed),
        ]
        let requirement = ToolTrustRequirement(
            kind: .drc,
            operationID: "run-drc",
            minimumLevel: .unknown,
            requiredInputFormats: [.oasis],
            requiredOutputFormats: [.json]
        )

        let selected = await registry.select(
            requirement: requirement,
            healthResults: health,
            artifactReader: qualification.reader
        )

        #expect(selected?.toolID == "smoke-tool")
    }

    @Test func selectSkipsFailedHealthCandidates() async throws {
        let qualification = try SmokeQualificationFixture()
        let registry = try ToolRegistry(descriptors: [
            try await qualification.descriptor(toolID: "failed"),
            try await qualification.descriptor(toolID: "healthy"),
        ])
        let health = [
            "failed": ToolHealthCheckResult(toolID: "failed", status: .failed),
            "healthy": ToolHealthCheckResult(toolID: "healthy", status: .passed),
        ]

        let selected = await registry.select(
            requirement: makeRequirement(),
            healthResults: health,
            artifactReader: qualification.reader
        )

        #expect(selected?.toolID == "healthy")
    }

    @Test func registryFailsClosedWhenQualifiedEvidenceCannotBeRead() async throws {
        let registry = try ToolRegistry(descriptors: [
            makeDescriptor(
                toolID: "corpus-tool",
                level: .corpusChecked,
                evidence: [ToolEvidence(evidenceID: "corpus", kind: .corpus)]
            ),
        ])

        let selected = await registry.select(
            requirement: ToolTrustRequirement(
                kind: .drc,
                operationID: "run-drc",
                minimumLevel: .corpusChecked,
                requiredInputFormats: [.oasis],
                requiredOutputFormats: [.json]
            ),
            healthResults: [
                "corpus-tool": ToolHealthCheckResult(toolID: "corpus-tool", status: .passed),
            ]
        )

        #expect(selected == nil)
    }

    @Test func initializerRejectsDuplicateToolIDs() {
        #expect(throws: ToolQualificationError.self) {
            try ToolRegistry(descriptors: [
                makeDescriptor(toolID: "drc", level: .unknown),
                makeDescriptor(toolID: "drc", level: .smokeChecked),
            ])
        }
    }

    @Test func initializerRejectsInvalidToolID() {
        #expect(throws: ToolQualificationError.invalidToolID("../drc")) {
            try ToolRegistry(descriptors: [
                makeDescriptor(toolID: "../drc", level: .unknown),
            ])
        }
    }

    @Test func initializerRejectsStructurallyInvalidDescriptor() {
        var descriptor = makeDescriptor(toolID: "drc", level: .unknown)
        descriptor.capabilities = []

        #expect(throws: ToolQualificationError.structurallyInvalidDescriptor("drc")) {
            try ToolRegistry(descriptors: [descriptor])
        }
    }

    @Test func upsertRejectsStructurallyInvalidDescriptor() throws {
        var registry = ToolRegistry()
        var descriptor = makeDescriptor(toolID: "drc", level: .unknown)
        descriptor.environment.platform = " "

        #expect(throws: ToolQualificationError.structurallyInvalidDescriptor("drc")) {
            try registry.upsert(descriptor)
        }
        #expect(registry.descriptor(toolID: "drc") == nil)
    }

    @Test func decoderRejectsDescriptorKeyMismatch() throws {
        let registry = try ToolRegistry(descriptors: [
            makeDescriptor(toolID: "drc", level: .unknown),
        ])
        let encoded = try JSONEncoder().encode(registry)
        let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let descriptor = try #require((json["descriptors"] as? [String: Any])?["drc"])
        let mismatched = try JSONSerialization.data(withJSONObject: [
            "descriptors": ["other": descriptor],
        ])

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ToolRegistry.self, from: mismatched)
        }
    }

    private func makeRequirement() -> ToolTrustRequirement {
        ToolTrustRequirement(
            kind: .drc,
            operationID: "run-drc",
            minimumLevel: .smokeChecked,
            requiredInputFormats: [.oasis],
            requiredOutputFormats: [.json]
        )
    }

    private func makeDescriptor(
        toolID: String,
        level: ToolQualificationLevel,
        evidence: [ToolEvidence] = []
    ) -> ToolDescriptor {
        ToolDescriptor(
            toolID: toolID,
            displayName: toolID,
            kind: .drc,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "run-drc",
                    inputFormats: [.oasis],
                    outputFormats: [.json]
                ),
            ],
            trustProfile: ToolTrustProfile(level: level, evidence: evidence),
            environment: ToolEnvironment(platform: "macOS", requiredAssets: [])
        )
    }
}

private struct SmokeQualificationFixture {
    let issuer: ProducerIdentity
    let checkedAt = Date(timeIntervalSince1970: 1_000)
    let reader = RegistryQualificationArtifactReader()

    init() throws {
        issuer = try ProducerIdentity(
            kind: .engine,
            identifier: "registry-qualification-runner",
            version: "1"
        )
    }

    func descriptor(toolID: String) async throws -> ToolDescriptor {
        let inputData = Data("input".utf8)
        let outputData = Data("output".utf8)
        let input = try artifact(id: "\(toolID)-input", data: inputData)
        let output = try artifact(id: "\(toolID)-output", data: outputData)
        await reader.insert(inputData, for: input)
        await reader.insert(outputData, for: output)
        let result = ToolSmokeQualificationResult(
            resultID: "\(toolID)-smoke",
            qualificationID: "\(toolID)-qualification",
            toolID: toolID,
            issuer: issuer,
            inputArtifacts: [input],
            outputArtifacts: [output],
            checkedAt: checkedAt
        )
        let data = try result.canonicalData()
        let reference = try artifact(id: "\(toolID)-smoke-result", data: data)
        await reader.insert(data, for: reference)
        return ToolDescriptor(
            toolID: toolID,
            displayName: toolID,
            kind: .drc,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "run-drc",
                    inputFormats: [.oasis],
                    outputFormats: [.json]
                ),
            ],
            trustProfile: ToolTrustProfile(
                level: .smokeChecked,
                evidence: [ToolEvidence(
                    evidenceID: result.resultID,
                    kind: .smoke,
                    artifact: reference,
                    checkedAt: checkedAt
                )]
            ),
            environment: ToolEnvironment(platform: "macOS", requiredAssets: [])
        )
    }

    private func artifact(id: String, data: Data) throws -> ArtifactReference {
        ArtifactReference(
            id: try ArtifactID(rawValue: id),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: "qualification/\(id).json"),
                role: .output,
                kind: .report,
                format: .json
            ),
            digest: try SHA256ContentDigester().digest(data: data, using: .sha256),
            byteCount: UInt64(data.count),
            producer: issuer
        )
    }
}

private actor RegistryQualificationArtifactReader: ToolQualificationArtifactReading {
    private var dataByReference: [ArtifactReference: Data] = [:]

    func insert(_ data: Data, for reference: ArtifactReference) {
        dataByReference[reference] = data
    }

    func verifiedData(for reference: ArtifactReference) async throws -> Data {
        guard let data = dataByReference[reference] else {
            throw ToolProcessQualificationEvidenceBuildError.artifactIntegrityFailed(
                reference.id.rawValue
            )
        }
        return data
    }
}
