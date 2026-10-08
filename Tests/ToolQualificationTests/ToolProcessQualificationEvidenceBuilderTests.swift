import Foundation
import Testing
import CircuiteFoundation
import CircuiteFoundationCrypto
import CircuiteFoundationFileSystem
import CircuiteFoundationFoundation

@testable import ToolQualification

@Suite("Tool process qualification evidence builder")
struct ToolProcessQualificationEvidenceBuilderTests {
    @Test("an executed but unobserved phase cannot promote a model")
    func excludesUnobservedPhaseModelCoverage() async throws {
        let fixture = try Fixture(phaseIDs: ["observed", "unobserved"],
            observedPhaseIDs: ["observed"], receiptPhaseIDs: ["observed", "unobserved"])
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        let evidence = try await ToolProcessQualificationEvidenceBuilder().build(
            fixture.request(now: now), reading: fixture.reader, at: now)
        #expect(evidence.qualifiedModelIDs == ["process-model-a"])
        try await ToolProcessQualificationEvidenceValidator().validate(evidence, reading: fixture.reader, at: now)
        await #expect(throws: ToolProcessQualificationEvidenceBuildError.unexecutedModels(["process-model-b"])) {
            _ = try await ToolProcessQualificationEvidenceBuilder().build(
                fixture.request(now: now, qualifiedModelIDs: ["process-model-b"]), reading: fixture.reader, at: now)
        }
    }

    @Test("distinct phases consume the same actual instance with different effective parameters")
    func acceptsSameActualInstanceAcrossPhases() async throws {
        let fixture = try Fixture(modelIDs: ["process-model-a", "process-model-a"],
            phaseIDs: ["point-1", "point-2"], observedPhaseIDs: ["point-1", "point-2"],
            receiptPhaseIDs: ["point-1", "point-2"], sharedInstanceID: "actual-instance")
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        let evidence = try await ToolProcessQualificationEvidenceBuilder().build(
            fixture.request(now: now), reading: fixture.reader, at: now)
        #expect(evidence.qualifiedModelIDs == ["process-model-a"])
        try await ToolProcessQualificationEvidenceValidator().validate(evidence, reading: fixture.reader, at: now)
    }

    @Test("validator cannot promote a retained but unobserved model phase")
    func validatorRejectsUnobservedPhaseCoverageClaim() async throws {
        let fixture = try Fixture(phaseIDs: ["observed", "unobserved"],
            observedPhaseIDs: ["observed"], receiptPhaseIDs: ["observed", "unobserved"])
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        let evidence = try await ToolProcessQualificationEvidenceBuilder().build(
            fixture.request(now: now), reading: fixture.reader, at: now)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(evidence)) as? [String: Any])
        object["qualifiedModelIDs"] = ["process-model-a", "process-model-b"]
        let forged = try JSONDecoder().decode(ToolProcessQualificationEvidence.self,
            from: JSONSerialization.data(withJSONObject: object))
        await #expect(throws: ToolProcessQualificationEvidenceBuildError.self) {
            try await ToolProcessQualificationEvidenceValidator().validate(forged, reading: fixture.reader, at: now)
        }
    }

    @Test("phase inventories and every metric binding are mandatory and complete",
        arguments: ["empty", "duplicate", "missing-metric", "extra-metric", "empty-binding", "duplicate-binding", "unknown-phase"])
    func refusesInvalidPhaseObservationBindings(_ invalidity: String) throws {
        let fixture = try Fixture(modelIDs: [])
        defer { fixture.remove() }
        let original = try fixture.execution(oracle: false)
        let phases = invalidity == "empty" ? [] : invalidity == "duplicate" ? ["analysis", "analysis"] : ["analysis"]
        var bindings = original.metricPhaseIDs
        switch invalidity {
        case "missing-metric": bindings = [:]
        case "extra-metric": bindings["extra"] = ["analysis"]
        case "empty-binding": bindings["case-result"] = []
        case "duplicate-binding": bindings["case-result"] = ["analysis", "analysis"]
        case "unknown-phase": bindings["case-result"] = ["unknown"]
        default: break
        }
        let invalid = ToolQualificationCaseExecution(caseID: original.caseID, executionID: original.executionID,
            producer: original.producer, executableArtifact: original.executableArtifact,
            inputArtifacts: original.inputArtifacts, phaseIDs: phases, metricPhaseIDs: bindings,
            modelReceiptArtifacts: original.modelReceiptArtifacts, observedMetrics: original.observedMetrics)
        #expect(!invalid.isStructurallyValid)
        #expect(throws: ToolProcessQualificationEvidenceBuildError.self) { _ = try invalid.canonicalData() }
    }

    @Test("phase intake cannot synthesize missing execution or receipt fields")
    func rejectsMissingMandatoryPhaseFields() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        for key in ["phaseIDs", "metricPhaseIDs"] {
            var original = try #require(JSONSerialization.jsonObject(with: fixture.execution(oracle: false).canonicalData()) as? [String: Any])
            original.removeValue(forKey: key)
            #expect(throws: DecodingError.self) {
                _ = try JSONDecoder().decode(ToolQualificationCaseExecution.self,
                    from: JSONSerialization.data(withJSONObject: original))
            }
        }
        for key in ["phaseID", "consumedInstances"] {
            var receipt = try #require(JSONSerialization.jsonObject(with: fixture.receipt(oracle: false).canonicalData()) as? [String: Any])
            receipt.removeValue(forKey: key)
            #expect(throws: DecodingError.self) {
                _ = try JSONDecoder().decode(ToolQualificationModelExecutionReceipt.self,
                    from: JSONSerialization.data(withJSONObject: receipt))
            }
        }
    }

    @Test("requested model IDs cannot qualify without executed model receipts")
    func rejectsRequestedModelWithoutExecutedReceipt() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        let request = fixture.request(now: now, qualifiedModelIDs: ["never-executed-model"])
        await #expect(throws: ToolProcessQualificationEvidenceBuildError.self) {
            _ = try await ToolProcessQualificationEvidenceBuilder().build(
                request, reading: fixture.reader, at: now
            )
        }
    }

    @Test("builder verifies and promotes a complete independent artifact graph")
    func buildsQualifiedRecord() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        let request = fixture.request(now: now, qualifiedModelIDs: ["process-model-b", "process-model-a"])

        let evidence = try await ToolProcessQualificationEvidenceBuilder().build(
            request,
            reading: fixture.reader,
            at: now
        )

        #expect(evidence.status == .qualified)
        #expect(evidence.isQualified(at: now, requirePDKScope: true))
        #expect(evidence.hasIndependentOracleEvidence)
        #expect(evidence.evidenceArtifactIDs == request.evidenceArtifacts.map { $0.id.description }.sorted())
        #expect(evidence.qualifiedModelIDs == ["process-model-a", "process-model-b"])
    }

    @Test("coverage is derived independently of requested model IDs")
    func derivesActualModelCoverageWithoutRequestedIDs() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        let evidence = try await ToolProcessQualificationEvidenceBuilder().build(
            fixture.request(now: now), reading: fixture.reader, at: now)
        #expect(evidence.qualifiedModelIDs == ["process-model-a", "process-model-b"])
        try await ToolProcessQualificationEvidenceValidator().validate(evidence, reading: fixture.reader, at: now)
    }

    @Test("domain CLI tool producers retain valid original execution and model receipts")
    func acceptsBoundToolProducer() async throws {
        let fixture = try Fixture(producerKind: .tool)
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        let evidence = try await ToolProcessQualificationEvidenceBuilder().build(
            fixture.request(now: now), reading: fixture.reader, at: now)
        #expect(evidence.qualifiedModelIDs == ["process-model-a", "process-model-b"])
        try await ToolProcessQualificationEvidenceValidator().validate(evidence, reading: fixture.reader, at: now)
    }

    @Test("non-executing producers cannot emit original execution or consumption receipts",
        arguments: ["human", "agent", "library"])
    func refusesNonExecutingProducerKind(_ rawKind: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try fixture.execution(oracle: false)
        let receipt = try fixture.receipt(oracle: false)
        let producer = try ProducerIdentity(kind: ProducerKind(rawValue: rawKind),
            identifier: original.producer.identifier, version: original.producer.version)
        let invalidExecution = ToolQualificationCaseExecution(caseID: original.caseID,
            executionID: original.executionID, producer: producer, executableArtifact: original.executableArtifact,
            inputArtifacts: original.inputArtifacts, phaseIDs: original.phaseIDs, metricPhaseIDs: original.metricPhaseIDs, modelReceiptArtifacts: original.modelReceiptArtifacts,
            observedMetrics: original.observedMetrics)
        let invalidReceipt = ToolQualificationModelExecutionReceipt(caseID: receipt.caseID,
            executionID: receipt.executionID, producer: producer, phaseID: receipt.phaseID, modelID: receipt.modelID,
            sourceArtifact: receipt.sourceArtifact, selectedModelIdentifier: receipt.selectedModelIdentifier,
            consumedInstances: receipt.consumedInstances, inputArtifacts: receipt.inputArtifacts,
            modelVersion: receipt.modelVersion, resolvedParameters: receipt.resolvedParameters)
        #expect(!invalidExecution.isStructurallyValid)
        #expect(!invalidReceipt.isStructurallyValid)
        #expect(throws: ToolProcessQualificationEvidenceBuildError.self) { _ = try invalidExecution.canonicalData() }
        #expect(throws: ToolProcessQualificationEvidenceBuildError.self) { _ = try invalidReceipt.canonicalData() }
    }

    @Test("model-free executions need no invented model receipts")
    func acceptsModelFreeExecutionAndRefusesRequestedModel() async throws {
        let fixture = try Fixture(modelIDs: [])
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        let evidence = try await ToolProcessQualificationEvidenceBuilder().build(
            fixture.request(now: now), reading: fixture.reader, at: now)
        #expect(evidence.qualifiedModelIDs.isEmpty)
        await #expect(throws: ToolProcessQualificationEvidenceBuildError.unexecutedModels(["unused"])) {
            _ = try await ToolProcessQualificationEvidenceBuilder().build(
                fixture.request(now: now, qualifiedModelIDs: ["unused"]), reading: fixture.reader, at: now)
        }
    }

    @Test("oracle primary must exactly join the corpus primary")
    func rejectsOraclePrimaryWithDifferentComparison() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        let primary = fixture.outcome(original: fixture.output, expected: 0.1, tolerance: 0.2)
        var request = fixture.request(now: now)
        request.oracleResultArtifacts = [try await fixture.storeOracle(primary: primary)]
        await #expect(throws: ToolProcessQualificationEvidenceBuildError.caseBindingMismatch(
            caseID: "case-1", reason: "oracle primary does not exactly match the corpus primary")) {
            _ = try await ToolProcessQualificationEvidenceBuilder().build(request, reading: fixture.reader, at: now)
        }
    }

    @Test("passing aggregate comparisons cannot forge original observations")
    func rejectsForgedOriginalObservations() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        var request = fixture.request(now: now)
        request.corpusResultArtifacts = [try await fixture.storeCorpus(
            outcome: fixture.outcome(original: fixture.output, observed: 1, expected: 1))]
        await #expect(throws: ToolProcessQualificationEvidenceBuildError.caseBindingMismatch(
            caseID: "case-1", reason: "original observations, executable, producer or retained inventory does not match")) {
            _ = try await ToolProcessQualificationEvidenceBuilder().build(request, reading: fixture.reader, at: now)
        }
    }

    @Test("the same case ID cannot hide conflicting corpus outcomes")
    func rejectsConflictingDuplicateCases() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        var request = fixture.request(now: now)
        request.corpusResultArtifacts.append(try await fixture.storeCorpus(
            outcome: fixture.outcome(original: fixture.output, expected: 0.1, tolerance: 0.2)))
        await #expect(throws: ToolProcessQualificationEvidenceBuildError.conflictingCase("case-1")) {
            _ = try await ToolProcessQualificationEvidenceBuilder().build(request, reading: fixture.reader, at: now)
        }
    }

    @Test("every executed corpus case needs a corresponding oracle case")
    func rejectsMissingMatchedCase() async throws {
        let fixture = try Fixture(modelIDs: [])
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        let original = try fixture.execution(oracle: false)
        let second = try await fixture.store("second-case", data: ToolQualificationCaseExecution(
            caseID: "case-2", executionID: "second-primary-run", producer: original.producer,
            executableArtifact: original.executableArtifact, inputArtifacts: original.inputArtifacts, phaseIDs: original.phaseIDs, metricPhaseIDs: original.metricPhaseIDs,
            modelReceiptArtifacts: [], observedMetrics: original.observedMetrics).canonicalData())
        let outcome = ToolQualificationCaseOutcome(caseID: "case-2", originalExecutionArtifact: second,
            coverageTags: ["fixture"], comparisons: [ToolQualificationMetricComparison(metricID: "case-result", observed: 0, expected: 0)])
        var request = fixture.request(now: now)
        request.outputArtifacts.append(second)
        request.corpusResultArtifacts = [try await fixture.store("corpus-second-case", data: ToolCorpusQualificationResult(
            resultID: "corpus-second-case", qualificationID: "qualification-1", toolID: fixture.scope.implementationID,
            scope: fixture.scope, issuer: fixture.issuer, inputArtifacts: fixture.inputs,
            outputArtifacts: [fixture.output, second],
            cases: [fixture.outcome(original: fixture.output), outcome], checkedAt: now).canonicalData())]
        await #expect(throws: ToolProcessQualificationEvidenceBuildError.missingCase("case-2")) {
            _ = try await ToolProcessQualificationEvidenceBuilder().build(request, reading: fixture.reader, at: now)
        }
    }

    @Test("original input and executable identities cannot be substituted")
    func rejectsDifferentOriginalInputOrExecutable() async throws {
        let fixture = try Fixture(modelIDs: [])
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        let original = try fixture.execution(oracle: true)
        let otherInput = try await fixture.store("different-case-input", data: Data("different input".utf8))
        let differentInputOutput = try await fixture.store("different-input-output", data: ToolQualificationCaseExecution(
            caseID: original.caseID, executionID: original.executionID, producer: original.producer,
            executableArtifact: original.executableArtifact, inputArtifacts: [otherInput], phaseIDs: original.phaseIDs, metricPhaseIDs: original.metricPhaseIDs,
            modelReceiptArtifacts: [], observedMetrics: original.observedMetrics).canonicalData())
        var inputRequest = fixture.request(now: now)
        inputRequest.inputArtifacts.append(otherInput)
        inputRequest.outputArtifacts.append(differentInputOutput)
        inputRequest.oracleResultArtifacts = [try await fixture.storeOracle(
            oracle: fixture.outcome(original: differentInputOutput), additionalInputs: [otherInput])]
        await #expect(throws: ToolProcessQualificationEvidenceBuildError.caseBindingMismatch(
            caseID: "case-1", reason: "independent executions require distinct outputs and receipts with identical case inputs and phase bindings")) {
            _ = try await ToolProcessQualificationEvidenceBuilder().build(inputRequest, reading: fixture.reader, at: now)
        }
        let wrongExecutableOutput = try await fixture.store("wrong-executable-output", data: ToolQualificationCaseExecution(
            caseID: original.caseID, executionID: original.executionID, producer: original.producer,
            executableArtifact: fixture.identity.toolExecutable, inputArtifacts: original.inputArtifacts, phaseIDs: original.phaseIDs, metricPhaseIDs: original.metricPhaseIDs,
            modelReceiptArtifacts: [], observedMetrics: original.observedMetrics).canonicalData())
        var executableRequest = fixture.request(now: now)
        executableRequest.outputArtifacts.append(wrongExecutableOutput)
        executableRequest.oracleResultArtifacts = [try await fixture.storeOracle(oracle: fixture.outcome(original: wrongExecutableOutput))]
        await #expect(throws: ToolProcessQualificationEvidenceBuildError.caseBindingMismatch(
            caseID: "case-1", reason: "original observations, executable, producer or retained inventory does not match")) {
            _ = try await ToolProcessQualificationEvidenceBuilder().build(executableRequest, reading: fixture.reader, at: now)
        }
    }

    @Test("independent model source, version, selection, phase and effective conditions must agree",
        arguments: ["geometry", "version", "selection", "source", "phase", "modelParameters"])
    func rejectsDifferentResolvedModelConditions(_ mismatch: String) async throws {
        let fixture = try Fixture(phaseIDs: ["analysis", "alternate"])
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        let original = try fixture.execution(oracle: true)
        let receipt = try fixture.receipt(oracle: true)
        let changedReceipt = ToolQualificationModelExecutionReceipt(
            caseID: receipt.caseID, executionID: receipt.executionID, producer: receipt.producer,
            phaseID: mismatch == "phase" ? "alternate" : receipt.phaseID,
            modelID: receipt.modelID, sourceArtifact: mismatch == "source" ? fixture.input : receipt.sourceArtifact,
            selectedModelIdentifier: mismatch == "selection" ? "different-selected-bin" : receipt.selectedModelIdentifier,
            consumedInstances: mismatch == "geometry" ? ["instance-0": ["width": 0.000002, "temperature": 300]] : receipt.consumedInstances,
            inputArtifacts: receipt.inputArtifacts, modelVersion: mismatch == "version" ? nil : receipt.modelVersion,
            resolvedParameters: mismatch == "modelParameters" ? ["threshold": 0.6] : receipt.resolvedParameters)
        let reference = try await fixture.store("changed-receipt", data: changedReceipt.canonicalData())
        let changedExecution = ToolQualificationCaseExecution(
            caseID: original.caseID, executionID: original.executionID, producer: original.producer,
            executableArtifact: original.executableArtifact, inputArtifacts: original.inputArtifacts, phaseIDs: original.phaseIDs, metricPhaseIDs: original.metricPhaseIDs,
            modelReceiptArtifacts: [reference] + Array(fixture.oracleReceipts.dropFirst()),
            observedMetrics: original.observedMetrics)
        let output = try await fixture.store("changed-oracle-output", data: changedExecution.canonicalData())
        var request = fixture.request(now: now)
        request.outputArtifacts += [reference, output]
        request.oracleResultArtifacts = [try await fixture.storeOracle(
            oracle: fixture.outcome(original: output), additionalOracleOutputs: [reference])]
        await #expect(throws: ToolProcessQualificationEvidenceBuildError.caseBindingMismatch(
            caseID: "case-1", reason: "primary and oracle selected model source, version, phases, instances or resolved conditions differ")) {
            _ = try await ToolProcessQualificationEvidenceBuilder().build(request, reading: fixture.reader, at: now)
        }
    }

    @Test("independent output artifacts cannot alias an execution identity")
    func rejectsAliasedExecutionIdentity() async throws {
        let fixture = try Fixture(modelIDs: [])
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        let primary = try fixture.execution(oracle: false)
        let oracle = try fixture.execution(oracle: true)
        let output = try await fixture.store("aliased-oracle-output", data: ToolQualificationCaseExecution(
            caseID: oracle.caseID, executionID: primary.executionID, producer: oracle.producer,
            executableArtifact: oracle.executableArtifact, inputArtifacts: oracle.inputArtifacts, phaseIDs: oracle.phaseIDs, metricPhaseIDs: oracle.metricPhaseIDs,
            modelReceiptArtifacts: [], observedMetrics: oracle.observedMetrics).canonicalData())
        var request = fixture.request(now: now)
        request.outputArtifacts.append(output)
        request.oracleResultArtifacts = [try await fixture.storeOracle(oracle: fixture.outcome(original: output))]
        await #expect(throws: ToolProcessQualificationEvidenceBuildError.caseBindingMismatch(
            caseID: "case-1", reason: "independent executions require distinct outputs and receipts with identical case inputs and phase bindings")) {
            _ = try await ToolProcessQualificationEvidenceBuilder().build(request, reading: fixture.reader, at: now)
        }
    }

    @Test("receipts refuse unknown phases and duplicate consumption within one phase",
        arguments: ["duplicate", "unknown-phase"])
    func rejectsDuplicateConsumedModelInstance(_ invalidity: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        let original = try fixture.execution(oracle: false)
        let receipt = try fixture.receipt(oracle: false)
        let duplicate = try await fixture.store("duplicate-receipt", data: ToolQualificationModelExecutionReceipt(
            caseID: receipt.caseID, executionID: receipt.executionID, producer: receipt.producer,
            phaseID: invalidity == "unknown-phase" ? "unknown" : receipt.phaseID,
            modelID: receipt.modelID, sourceArtifact: receipt.sourceArtifact,
            selectedModelIdentifier: "conflicting-selected-model", consumedInstances: receipt.consumedInstances,
            inputArtifacts: receipt.inputArtifacts, modelVersion: receipt.modelVersion,
            resolvedParameters: receipt.resolvedParameters).canonicalData())
        let output = try await fixture.store("duplicate-receipt-output", data: ToolQualificationCaseExecution(
            caseID: original.caseID, executionID: original.executionID, producer: original.producer,
            executableArtifact: original.executableArtifact, inputArtifacts: original.inputArtifacts, phaseIDs: original.phaseIDs, metricPhaseIDs: original.metricPhaseIDs,
            modelReceiptArtifacts: original.modelReceiptArtifacts + [duplicate],
            observedMetrics: original.observedMetrics).canonicalData())
        var request = fixture.request(now: now)
        request.outputArtifacts += [output, duplicate]
        request.corpusResultArtifacts = [try await fixture.store("duplicate-receipt-corpus", data: ToolCorpusQualificationResult(
            resultID: "duplicate-receipt-corpus", qualificationID: "qualification-1", toolID: fixture.scope.implementationID,
            scope: fixture.scope, issuer: fixture.issuer, inputArtifacts: fixture.inputs,
            outputArtifacts: [output, duplicate] + fixture.primaryReceipts,
            cases: [fixture.outcome(original: output)], checkedAt: now).canonicalData())]
        await #expect(throws: ToolProcessQualificationEvidenceBuildError.caseBindingMismatch(
            caseID: "case-1", reason: "receipt has a different execution/input/phase binding or duplicates a consumed instance within one phase")) {
            _ = try await ToolProcessQualificationEvidenceBuilder().build(request, reading: fixture.reader, at: now)
        }
    }

    @Test("independent executions must agree on completed phases and metric contributors",
        arguments: ["inventory", "metric-binding"])
    func rejectsDifferentOraclePhaseBindings(_ mismatch: String) async throws {
        let fixture = try Fixture(modelIDs: [], phaseIDs: ["analysis", "alternate"])
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        let original = try fixture.execution(oracle: true)
        let changed = ToolQualificationCaseExecution(caseID: original.caseID, executionID: original.executionID,
            producer: original.producer, executableArtifact: original.executableArtifact,
            inputArtifacts: original.inputArtifacts,
            phaseIDs: mismatch == "inventory" ? ["analysis"] : original.phaseIDs,
            metricPhaseIDs: mismatch == "metric-binding" ? ["case-result": ["alternate"]] : original.metricPhaseIDs,
            modelReceiptArtifacts: [], observedMetrics: original.observedMetrics)
        let output = try await fixture.store("different-oracle-phases", data: changed.canonicalData())
        var request = fixture.request(now: now)
        request.outputArtifacts.append(output)
        request.oracleResultArtifacts = [try await fixture.storeOracle(oracle: fixture.outcome(original: output))]
        await #expect(throws: ToolProcessQualificationEvidenceBuildError.caseBindingMismatch(
            caseID: "case-1", reason: "independent executions require distinct outputs and receipts with identical case inputs and phase bindings")) {
            _ = try await ToolProcessQualificationEvidenceBuilder().build(request, reading: fixture.reader, at: now)
        }
    }

    @Test("retained model receipt bytes are independently verified even for unobserved phases", arguments: [0, 1])
    func rejectsAlteredModelReceipt(_ index: Int) async throws {
        let fixture = try Fixture(phaseIDs: ["observed", "unobserved"],
            observedPhaseIDs: ["observed"], receiptPhaseIDs: ["observed", "unobserved"])
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        try Data("altered receipt".utf8).write(
            to: fixture.root.appending(path: "qualification/primary-run-receipt-\(index).json"), options: .atomic)
        await #expect(throws: ToolProcessQualificationEvidenceBuildError.artifactIntegrityFailed(
            fixture.primaryReceipts[index].id.description)) {
            _ = try await ToolProcessQualificationEvidenceBuilder().build(
                fixture.request(now: now), reading: fixture.reader, at: now)
        }
    }

    @Test("missing nested receipt and source bindings fail closed")
    func rejectsMissingNestedReceiptsAndSources() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        var missingReceipt = fixture.request(now: now)
        missingReceipt.outputArtifacts.removeAll { $0 == fixture.primaryReceipts[0] }
        await #expect(throws: ToolProcessQualificationEvidenceBuildError.self) {
            _ = try await ToolProcessQualificationEvidenceBuilder().build(missingReceipt, reading: fixture.reader, at: now)
        }
        var missingSource = fixture.request(now: now)
        missingSource.inputArtifacts.removeAll { $0 == fixture.modelSource }
        await #expect(throws: ToolProcessQualificationEvidenceBuildError.self) {
            _ = try await ToolProcessQualificationEvidenceBuilder().build(missingSource, reading: fixture.reader, at: now)
        }
    }

    @Test("validator does not use a forged model claim as reconstruction input")
    func rejectsForgedEvidenceModelCoverage() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        let evidence = try await ToolProcessQualificationEvidenceBuilder().build(
            fixture.request(now: now), reading: fixture.reader, at: now)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(evidence)) as? [String: Any])
        object["qualifiedModelIDs"] = evidence.qualifiedModelIDs + ["forged-model"]
        let forged = try JSONDecoder().decode(ToolProcessQualificationEvidence.self,
            from: JSONSerialization.data(withJSONObject: object))
        await #expect(throws: ToolProcessQualificationEvidenceBuildError.self) {
            try await ToolProcessQualificationEvidenceValidator().validate(forged, reading: fixture.reader, at: now)
        }
    }

    @Test("validator independently checks original outputs and model sources")
    func validatorRejectsChangedOriginalOutputAndModelSource() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        let evidence = try await ToolProcessQualificationEvidenceBuilder().build(
            fixture.request(now: now), reading: fixture.reader, at: now)
        let originalURL = fixture.root.appending(path: "qualification/output.json")
        let originalBytes = try Data(contentsOf: originalURL)
        try Data("changed original observations".utf8).write(to: originalURL, options: .atomic)
        await #expect(throws: ToolProcessQualificationEvidenceBuildError.artifactIntegrityFailed(fixture.output.id.description)) {
            try await ToolProcessQualificationEvidenceValidator().validate(evidence, reading: fixture.reader, at: now)
        }
        try originalBytes.write(to: originalURL, options: .atomic)
        try Data("changed model source".utf8).write(
            to: fixture.root.appending(path: "qualification/model-source.json"), options: .atomic)
        await #expect(throws: ToolProcessQualificationEvidenceBuildError.artifactIntegrityFailed(fixture.modelSource.id.description)) {
            try await ToolProcessQualificationEvidenceValidator().validate(evidence, reading: fixture.reader, at: now)
        }
    }

    @Test("receipts preserve unknown version and refuse unused or nonfinite model claims")
    func receiptAdmissionRequiresConsumptionAndFiniteConditions() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let receipt = try fixture.receipt(oracle: false)
        let unknown = ToolQualificationModelExecutionReceipt(caseID: receipt.caseID, executionID: receipt.executionID,
            producer: receipt.producer, phaseID: receipt.phaseID, modelID: receipt.modelID, sourceArtifact: receipt.sourceArtifact,
            selectedModelIdentifier: receipt.selectedModelIdentifier, consumedInstances: receipt.consumedInstances,
            inputArtifacts: receipt.inputArtifacts, resolvedParameters: receipt.resolvedParameters)
        let decoded = try ToolQualificationModelExecutionReceipt.decodeCanonical(from: unknown.canonicalData())
        #expect(decoded.modelVersion == nil)
        let invalidCases: [([String: [String: Double]], [String: Double])] = [
            ([:], ["threshold": 0.5]),
            (["instance-0": ["temperature": 300]], ["threshold": .infinity]),
            (["instance-0": ["temperature": .infinity]], ["threshold": 0.5]),
            (["": ["temperature": 300]], ["threshold": 0.5])
        ]
        for (instances, parameters) in invalidCases {
            let invalid = ToolQualificationModelExecutionReceipt(caseID: receipt.caseID, executionID: receipt.executionID,
                producer: receipt.producer, phaseID: receipt.phaseID, modelID: receipt.modelID, sourceArtifact: receipt.sourceArtifact,
                selectedModelIdentifier: receipt.selectedModelIdentifier, consumedInstances: instances,
                inputArtifacts: receipt.inputArtifacts, resolvedParameters: parameters)
            #expect(!invalid.isStructurallyValid)
            #expect(throws: ToolProcessQualificationEvidenceBuildError.self) { _ = try invalid.canonicalData() }
        }
    }

    @Test("builder requires corpus and independent oracle coverage for every requested corner")
    func requiresCompleteOperatingCornerCoverage() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        let qualified = fixture.request(
            now: now,
            requiredOperatingCornerIDs: ["tt", "ss", "ff"]
        )

        let evidence = try await ToolProcessQualificationEvidenceBuilder().build(
            qualified,
            reading: fixture.reader,
            at: now
        )
        #expect(evidence.qualifiedOperatingCornerIDs == ["ff", "ss", "tt"])

        let missing = fixture.request(
            now: now,
            requiredOperatingCornerIDs: ["tt", "ss", "ff", "sf"]
        )
        await #expect(throws: ToolProcessQualificationEvidenceBuildError.self) {
            _ = try await ToolProcessQualificationEvidenceBuilder().build(
                missing,
                reading: fixture.reader,
                at: now
            )
        }
    }

    @Test("builder derives pass status and rejects a failed canonical corpus result")
    func rejectsFailedCorpusResult() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        var request = fixture.request(now: now)
        request.corpusResultArtifacts = [try await fixture.failedCorpusResult(now: now)]

        await #expect(throws: ToolProcessQualificationEvidenceBuildError.self) {
            _ = try await ToolProcessQualificationEvidenceBuilder().build(
                request,
                reading: fixture.reader,
                at: now
            )
        }
    }

    @Test("builder rejects an artifact changed after it was referenced")
    func rejectsChangedArtifact() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        let request = fixture.request(now: now)
        try Data("changed".utf8).write(
            to: fixture.root.appendingPathComponent("qualification/oracle-evidence.json"),
            options: .atomic
        )

        do {
            _ = try await ToolProcessQualificationEvidenceBuilder().build(
                request,
                reading: fixture.reader,
                at: now
            )
            Issue.record("Changed evidence must not be promoted")
        } catch let error as ToolProcessQualificationEvidenceBuildError {
            #expect(error.localizedDescription.contains("integrity failed"))
        }
    }

    @Test("builder rejects an expired qualification window")
    func rejectsExpiredQualificationWindow() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        let request = fixture.request(now: now.addingTimeInterval(-200))

        await #expect(throws: ToolProcessQualificationEvidenceBuildError.notValidAt) {
            _ = try await ToolProcessQualificationEvidenceBuilder().build(
                request,
                reading: fixture.reader,
                at: now
            )
        }
    }

    @Test("builder rejects nonfinite qualification timestamps")
    func rejectsNonfiniteQualificationTimestamp() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        var request = fixture.request(now: now)
        request.expiresAt = Date(timeIntervalSinceReferenceDate: .infinity)

        await #expect(throws: ToolProcessQualificationEvidenceBuildError.self) {
            _ = try await ToolProcessQualificationEvidenceBuilder().build(
                request,
                reading: fixture.reader,
                at: now
            )
        }
    }

    @Test("builder rejects a qualification graph without an independent oracle result")
    func rejectsMissingOracleResult() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        var request = fixture.request(now: now)
        request.oracleResultArtifacts = []

        await #expect(throws: ToolProcessQualificationEvidenceBuildError.missingEvidence(.oracle)) {
            _ = try await ToolProcessQualificationEvidenceBuilder().build(
                request,
                reading: fixture.reader,
                at: now
            )
        }
    }

    @Test("oracle result requires distinct primary and oracle output artifacts")
    func rejectsSharedOracleOutputArtifact() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let result = ToolOracleQualificationResult(
            resultID: "oracle-shared-output",
            qualificationID: "qualification-1",
            primaryToolID: "qualified-scan",
            oracleToolID: "independent-scan-oracle",
            scope: fixture.scope,
            issuer: fixture.issuer,
            inputArtifacts: fixture.inputs,
            primaryOutputArtifacts: [fixture.output],
            oracleOutputArtifacts: [fixture.output],
            cases: [fixture.passingOracleCase()],
            checkedAt: Date(timeIntervalSince1970: 1_000)
        )

        #expect(!result.isStructurallyValid)
        #expect(throws: ToolProcessQualificationEvidenceBuildError.self) {
            _ = try result.canonicalData()
        }
    }

    @Test("oracle agreement values must be bound to both case outcomes")
    func rejectsUnboundOracleAgreementValues() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let primary = ToolQualificationCaseOutcome(
            caseID: "case-1",
            originalExecutionArtifact: fixture.output,
            coverageTags: ["fixture"],
            comparisons: [ToolQualificationMetricComparison(
                metricID: "metric",
                observed: 0,
                expected: 0
            )]
        )
        let oracle = ToolQualificationCaseOutcome(
            caseID: "case-1",
            originalExecutionArtifact: fixture.oracleOutput,
            coverageTags: ["fixture"],
            comparisons: [ToolQualificationMetricComparison(
                metricID: "metric",
                observed: 1,
                expected: 1
            )]
        )
        let comparison = ToolOracleCaseComparison(
            caseID: "case-1",
            primary: primary,
            oracle: oracle,
            agreementComparisons: [ToolOracleMetricComparison(
                metricID: "metric",
                primaryObserved: 0,
                oracleObserved: 0
            )]
        )

        #expect(!comparison.isStructurallyValid)
        #expect(!comparison.agreed)
    }

    @Test("persisted qualification contracts require their exact current schema")
    func rejectsMissingAndUnsupportedSchemaVersions() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        let request = fixture.request(now: now)
        let evidence = try await ToolProcessQualificationEvidenceBuilder().build(
            request,
            reading: fixture.reader,
            at: now
        )

        try expectCurrentSchema(
            ToolCorpusQualificationResult.self,
            data: Data(contentsOf: fixture.root.appending(path: "qualification/corpus-evidence.json"))
        )
        try expectCurrentSchema(
            ToolOracleQualificationResult.self,
            data: Data(contentsOf: fixture.root.appending(path: "qualification/oracle-evidence.json"))
        )
        try expectCurrentSchema(
            ToolHealthQualificationResult.self,
            data: Data(contentsOf: fixture.root.appending(path: "qualification/health-evidence.json"))
        )
        try expectCurrentSchema(
            ToolProcessQualificationEvidenceBuildRequest.self,
            data: JSONEncoder().encode(request)
        )
        try expectCurrentSchema(
            ToolProcessQualificationEvidence.self,
            data: JSONEncoder().encode(evidence)
        )
        try expectCurrentSchema(ToolQualificationCaseOutcome.self,
            data: JSONEncoder().encode(fixture.outcome(original: fixture.output)))
        try expectCurrentSchema(ToolQualificationCaseExecution.self,
            data: JSONEncoder().encode(fixture.execution(oracle: false)))
        try expectCurrentSchema(ToolQualificationModelExecutionReceipt.self,
            data: JSONEncoder().encode(fixture.receipt(oracle: false)))
    }

    @Test("legacy case outcomes without original execution bindings are rejected")
    func rejectsLegacyOutcomeWithoutOriginalExecution() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var object = try #require(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(fixture.outcome(original: fixture.output))) as? [String: Any])
        object.removeValue(forKey: "originalExecutionArtifact")
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(ToolQualificationCaseOutcome.self, from: data)
        }
    }

    @Test("production record validation reconstructs the issuer's exact trust requirement")
    func productionRecordIssuerValidatorRoundTrip() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        let processEvidence = try await ToolProcessQualificationEvidenceBuilder().build(
            fixture.request(now: now),
            reading: fixture.reader,
            at: now
        )
        let descriptor = ToolDescriptor(
            toolID: processEvidence.toolID,
            displayName: "Qualified Scan",
            kind: .rtlVerification,
            version: processEvidence.scope.toolVersion,
            capabilities: [ToolCapability(operationID: "scan")],
            trustProfile: ToolTrustProfile(
                level: .productionEligible,
                evidence: processEvidence.corpusEvidence
                    + processEvidence.oracleEvidence
                    + processEvidence.healthEvidence,
                processQualification: processEvidence
            ),
            environment: ToolEnvironment(platform: "macOS", requiredAssets: [])
        )
        let record = try await DefaultToolQualificationRecordIssuer().issue(
            recordID: "production-scan-record",
            descriptor: descriptor,
            health: ToolHealthCheckResult(
                toolID: descriptor.toolID,
                status: .passed
            ),
            issuer: fixture.issuer,
            reading: fixture.reader,
            issuedAt: now
        )
        let reference = try await fixture.store(record: record)

        let validated = try await ToolQualificationRecordValidator().validatedRecord(
            referencedBy: reference,
            expectedToolID: descriptor.toolID,
            reading: fixture.reader
        )

        #expect(validated == record)
        #expect(validated.issuanceDecisions.allSatisfy {
            $0.decision.status == .eligible
        })
    }

    private func expectCurrentSchema<Value: Decodable>(
        _ type: Value.Type,
        data: Data
    ) throws {
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let currentVersion = try #require(object["schemaVersion"] as? Int)

        object.removeValue(forKey: "schemaVersion")
        let missing = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(type, from: missing)
        }

        object["schemaVersion"] = 9_999
        let unsupported = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(type, from: unsupported)
        }
        object["schemaVersion"] = currentVersion - 1
        let obsolete = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(type, from: obsolete)
        }
    }
}

private struct Fixture {
    let root: URL
    let scope: ToolQualificationScope
    let identity: ToolProcessQualificationArtifacts
    let corpus: ArtifactReference
    let oracle: ArtifactReference
    let health: ArtifactReference
    let input: ArtifactReference
    let output: ArtifactReference
    let oracleOutput: ArtifactReference
    let modelSource: ArtifactReference
    let primaryReceipts: [ArtifactReference]
    let oracleReceipts: [ArtifactReference]
    let issuer: ProducerIdentity
    let reader: VerifiedFileQualificationArtifactReader

    init(modelIDs: [String] = ["process-model-a", "process-model-b"], producerKind: ProducerKind = .engine,
        phaseIDs: [String] = ["analysis"], observedPhaseIDs: [String] = ["analysis"],
        receiptPhaseIDs: [String]? = nil, sharedInstanceID: String? = nil) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tool-qualification-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let tool = try Self.artifact("tool", root: root)
        let process = try Self.artifact("process", root: root)
        let pdk = try Self.artifact("pdk", root: root)
        let deck = try Self.artifact("deck", root: root)
        let oracleTool = try Self.artifact("oracle-tool", root: root)
        identity = ToolProcessQualificationArtifacts(
            toolExecutable: tool,
            processProfile: process,
            pdk: pdk,
            ruleDeck: deck,
            oracleExecutable: oracleTool
        )
        input = try Self.artifact("input", root: root)
        modelSource = try Self.artifact("model-source", root: root)
        issuer = try ProducerIdentity(
            kind: .engine,
            identifier: "qualification-runner",
            version: "1.0.0"
        )
        scope = ToolQualificationScope(
            implementationID: "qualified-scan",
            toolVersion: "1.0.0",
            binaryDigest: tool.digest.hexadecimalValue,
            algorithmVersion: "scan-v1",
            processProfileID: "fixture-process",
            processProfileDigest: process.digest.hexadecimalValue,
            deckDigest: deck.digest.hexadecimalValue,
            pdkID: "fixture-pdk",
            pdkDigest: pdk.digest.hexadecimalValue,
            oracle: ToolOracleQualificationScope(
                implementationID: "independent-scan-oracle",
                version: "2.0.0",
                binaryDigest: oracleTool.digest.hexadecimalValue
            )
        )
        let inputs = [input, modelSource]
        let primaryProducer = try ProducerIdentity(kind: producerKind, identifier: scope.implementationID, version: scope.toolVersion)
        let oracleProducer = try ProducerIdentity(kind: producerKind, identifier: "independent-scan-oracle", version: "2.0.0")
        primaryReceipts = try Self.receipts(root: root, inputs: inputs, source: modelSource,
            producer: primaryProducer, executionID: "primary-run", modelIDs: modelIDs,
            phaseIDs: receiptPhaseIDs, sharedInstanceID: sharedInstanceID)
        oracleReceipts = try Self.receipts(root: root, inputs: inputs, source: modelSource,
            producer: oracleProducer, executionID: "oracle-run", modelIDs: modelIDs,
            phaseIDs: receiptPhaseIDs, sharedInstanceID: sharedInstanceID)
        output = try Self.artifact("output", root: root, data: ToolQualificationCaseExecution(
            caseID: "case-1", executionID: "primary-run", producer: primaryProducer,
            executableArtifact: tool, inputArtifacts: inputs, phaseIDs: phaseIDs, metricPhaseIDs: ["case-result": observedPhaseIDs], modelReceiptArtifacts: primaryReceipts,
            observedMetrics: ["case-result": 0]
        ).canonicalData())
        oracleOutput = try Self.artifact("oracle-output", root: root, data: ToolQualificationCaseExecution(
            caseID: "case-1", executionID: "oracle-run", producer: oracleProducer,
            executableArtifact: oracleTool, inputArtifacts: inputs, phaseIDs: phaseIDs, metricPhaseIDs: ["case-result": observedPhaseIDs], modelReceiptArtifacts: oracleReceipts,
            observedMetrics: ["case-result": 0]
        ).canonicalData())
        let checkedAt = Date(timeIntervalSince1970: 1_000)
        corpus = try Self.artifact(
            "corpus-evidence",
            root: root,
            data: ToolCorpusQualificationResult(
                resultID: "corpus",
                qualificationID: "qualification-1",
                toolID: "qualified-scan",
                scope: scope,
                issuer: issuer,
                inputArtifacts: inputs,
                outputArtifacts: [output] + primaryReceipts,
                coverage: ToolQualificationCoverage(
                    operatingCornerIDs: ["tt", "ss", "ff"]
                ),
                cases: [Self.passingCase("case-1", original: output)],
                checkedAt: checkedAt
            ).canonicalData()
        )
        oracle = try Self.artifact(
            "oracle-evidence",
            root: root,
            data: ToolOracleQualificationResult(
                resultID: "oracle",
                qualificationID: "qualification-1",
                primaryToolID: "qualified-scan",
                oracleToolID: "independent-scan-oracle",
                scope: scope,
                issuer: issuer,
                inputArtifacts: inputs,
                primaryOutputArtifacts: [output] + primaryReceipts,
                oracleOutputArtifacts: [oracleOutput] + oracleReceipts,
                coverage: ToolQualificationCoverage(
                    operatingCornerIDs: ["tt", "ss", "ff"]
                ),
                cases: [Self.passingOracleCase("case-1", primary: output, oracle: oracleOutput)],
                checkedAt: checkedAt
            ).canonicalData()
        )
        health = try Self.artifact(
            "health-evidence",
            root: root,
            data: ToolHealthQualificationResult(
                resultID: "health",
                qualificationID: "qualification-1",
                toolID: "qualified-scan",
                scope: scope,
                issuer: issuer,
                inputArtifacts: inputs,
                outputArtifacts: [output],
                checkedAt: checkedAt
            ).canonicalData()
        )
        var urlsByArtifactID: [ArtifactID: URL] = [
            tool.id: Self.url("tool", root: root),
            process.id: Self.url("process", root: root),
            pdk.id: Self.url("pdk", root: root),
            deck.id: Self.url("deck", root: root),
            oracleTool.id: Self.url("oracle-tool", root: root),
            input.id: Self.url("input", root: root),
            output.id: Self.url("output", root: root),
            oracleOutput.id: Self.url("oracle-output", root: root),
            corpus.id: Self.url("corpus-evidence", root: root),
            oracle.id: Self.url("oracle-evidence", root: root),
            health.id: Self.url("health-evidence", root: root),
            modelSource.id: Self.url("model-source", root: root),
        ]
        for (index, receipt) in primaryReceipts.enumerated() {
            urlsByArtifactID[receipt.id] = Self.url("primary-run-receipt-\(index)", root: root)
        }
        for (index, receipt) in oracleReceipts.enumerated() {
            urlsByArtifactID[receipt.id] = Self.url("oracle-run-receipt-\(index)", root: root)
        }
        reader = VerifiedFileQualificationArtifactReader(urlsByArtifactID: urlsByArtifactID)
    }

    var inputs: [ArtifactReference] { [input, modelSource] }
    var outputs: [ArtifactReference] { [output, oracleOutput] + primaryReceipts + oracleReceipts }

    func passingOracleCase() -> ToolOracleCaseComparison {
        Self.passingOracleCase("case-1", primary: output, oracle: oracleOutput)
    }

    func outcome(original: ArtifactReference, observed: Double = 0, expected: Double = 0,
        tolerance: Double = 0) -> ToolQualificationCaseOutcome {
        ToolQualificationCaseOutcome(caseID: "case-1", originalExecutionArtifact: original,
            coverageTags: ["fixture"], comparisons: [ToolQualificationMetricComparison(
                metricID: "case-result", observed: observed, expected: expected, absoluteTolerance: tolerance)])
    }

    func execution(oracle: Bool) throws -> ToolQualificationCaseExecution {
        try ToolQualificationCaseExecution.decodeCanonical(from: Data(contentsOf:
            Self.url(oracle ? "oracle-output" : "output", root: root)))
    }

    func receipt(oracle: Bool) throws -> ToolQualificationModelExecutionReceipt {
        try ToolQualificationModelExecutionReceipt.decodeCanonical(from: Data(contentsOf:
            Self.url(oracle ? "oracle-run-receipt-0" : "primary-run-receipt-0", root: root)))
    }

    func store(_ name: String, data: Data) async throws -> ArtifactReference {
        let reference = try Self.artifact(name, root: root, data: data)
        await reader.insert(Self.url(name, root: root), for: reference.id)
        return reference
    }

    func storeCorpus(outcome: ToolQualificationCaseOutcome) async throws -> ArtifactReference {
        try await store("changed-corpus", data: ToolCorpusQualificationResult(
            resultID: "changed-corpus", qualificationID: "qualification-1", toolID: scope.implementationID,
            scope: scope, issuer: issuer, inputArtifacts: inputs,
            outputArtifacts: [outcome.originalExecutionArtifact] + primaryReceipts,
            cases: [outcome], checkedAt: Date(timeIntervalSince1970: 1_000)).canonicalData())
    }

    func storeOracle(primary: ToolQualificationCaseOutcome? = nil, oracle: ToolQualificationCaseOutcome? = nil,
        additionalOracleOutputs: [ArtifactReference] = [], additionalInputs: [ArtifactReference] = []) async throws -> ArtifactReference {
        let primaryOutcome = primary ?? outcome(original: output)
        let oracleOutcome = oracle ?? outcome(original: oracleOutput)
        return try await store("changed-oracle", data: ToolOracleQualificationResult(
            resultID: "changed-oracle", qualificationID: "qualification-1", primaryToolID: scope.implementationID,
            oracleToolID: "independent-scan-oracle", scope: scope, issuer: issuer, inputArtifacts: inputs + additionalInputs,
            primaryOutputArtifacts: [primaryOutcome.originalExecutionArtifact] + primaryReceipts,
            oracleOutputArtifacts: [oracleOutcome.originalExecutionArtifact] + oracleReceipts + additionalOracleOutputs,
            cases: [ToolOracleCaseComparison(caseID: "case-1", primary: primaryOutcome, oracle: oracleOutcome,
                agreementComparisons: [ToolOracleMetricComparison(metricID: "case-result",
                    primaryObserved: primaryOutcome.comparisons[0].observed,
                    oracleObserved: oracleOutcome.comparisons[0].observed)])],
            checkedAt: Date(timeIntervalSince1970: 1_000)).canonicalData())
    }

    func request(
        now: Date,
        qualifiedModelIDs: [String] = [],
        requiredOperatingCornerIDs: [String] = []
    ) -> ToolProcessQualificationEvidenceBuildRequest {
        ToolProcessQualificationEvidenceBuildRequest(
            qualificationID: "qualification-1",
            toolID: "qualified-scan",
            scope: scope,
            identityArtifacts: identity,
            corpusResultArtifacts: [corpus],
            oracleResultArtifacts: [oracle],
            healthResultArtifacts: [health],
            inputArtifacts: inputs,
            outputArtifacts: outputs,
            qualifiedModelIDs: qualifiedModelIDs,
            requiredOperatingCornerIDs: requiredOperatingCornerIDs,
            qualifiedAt: now.addingTimeInterval(-10),
            expiresAt: now.addingTimeInterval(100)
        )
    }

    func failedCorpusResult(now: Date) async throws -> ArtifactReference {
        let reference = try Self.artifact(
            "corpus-evidence",
            root: root,
            data: ToolCorpusQualificationResult(
                resultID: "corpus",
                qualificationID: "qualification-1",
                toolID: "qualified-scan",
                scope: scope,
                issuer: issuer,
                inputArtifacts: inputs,
                outputArtifacts: [output] + primaryReceipts,
                cases: [ToolQualificationCaseOutcome(
                    caseID: "case-1",
                    originalExecutionArtifact: output,
                    coverageTags: ["fixture"],
                    comparisons: [ToolQualificationMetricComparison(
                        metricID: "case-result",
                        observed: 1,
                        expected: 0
                    )]
                )],
                checkedAt: now
            ).canonicalData()
        )
        await reader.insert(
            Self.url("corpus-evidence", root: root),
            for: reference.id
        )
        return reference
    }

    func store(record: ToolQualificationRecord) async throws -> ArtifactReference {
        let data = try record.canonicalData()
        let reference = try Self.artifact(
            "production-record",
            root: root,
            data: data
        )
        await reader.insert(
            Self.url("production-record", root: root),
            for: reference.id
        )
        return reference
    }

    func remove() {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove fixture: \(error.localizedDescription)")
        }
    }

    private static func passingCase(_ caseID: String, original: ArtifactReference) -> ToolQualificationCaseOutcome {
        ToolQualificationCaseOutcome(
            caseID: caseID,
            originalExecutionArtifact: original,
            coverageTags: ["fixture"],
            comparisons: [ToolQualificationMetricComparison(
                metricID: "case-result",
                observed: 0,
                expected: 0
            )]
        )
    }

    private static func passingOracleCase(_ caseID: String, primary: ArtifactReference, oracle: ArtifactReference) -> ToolOracleCaseComparison {
        ToolOracleCaseComparison(
            caseID: caseID,
            primary: passingCase(caseID, original: primary),
            oracle: passingCase(caseID, original: oracle),
            agreementComparisons: [ToolOracleMetricComparison(
                metricID: "case-result",
                primaryObserved: 0,
                oracleObserved: 0
            )]
        )
    }

    private static func receipts(
        root: URL, inputs: [ArtifactReference], source: ArtifactReference,
        producer: ProducerIdentity, executionID: String, modelIDs: [String],
        phaseIDs: [String]?, sharedInstanceID: String?
    ) throws -> [ArtifactReference] {
        try modelIDs.enumerated().map { index, modelID in
            try artifact("\(executionID)-receipt-\(index)", root: root,
                data: ToolQualificationModelExecutionReceipt(
                    caseID: "case-1", executionID: executionID, producer: producer,
                    phaseID: phaseIDs?[index] ?? "analysis",
                    modelID: modelID, sourceArtifact: source, selectedModelIdentifier: "selected-\(modelID)",
                    consumedInstances: [sharedInstanceID ?? "instance-\(index)": ["width": 0.000001 * Double(index + 1), "temperature": 300]], inputArtifacts: inputs,
                    modelVersion: "declared-v1", resolvedParameters: ["threshold": 0.5]
                ).canonicalData())
        }
    }

    private static func artifact(
        _ name: String,
        root: URL,
        data: Data? = nil
    ) throws -> ArtifactReference {
        let relativePath = "qualification/\(name).json"
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try (data ?? Data("artifact:\(name)".utf8)).write(to: url, options: .atomic)
        return try LocalArtifactReferencer().reference(
            ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: relativePath),
                role: .output,
                kind: .evidence,
                format: .json
            ),
            relativeTo: root
        )
    }

    private static func url(_ name: String, root: URL) -> URL {
        root.appending(path: "qualification/\(name).json")
    }
}

private actor VerifiedFileQualificationArtifactReader: ToolQualificationArtifactReading {
    private var urlsByArtifactID: [ArtifactID: URL]

    init(urlsByArtifactID: [ArtifactID: URL]) {
        self.urlsByArtifactID = urlsByArtifactID
    }

    func insert(_ url: URL, for artifactID: ArtifactID) {
        urlsByArtifactID[artifactID] = url
    }

    func verifiedData(for reference: ArtifactReference) async throws -> Data {
        guard let url = urlsByArtifactID[reference.id] else {
            throw ToolProcessQualificationEvidenceBuildError.artifactAvailabilityMissing(
                reference.id.description
            )
        }
        let data = try Data(contentsOf: url)
        let digest = try SHA256ContentDigester().digest(data: data, using: .sha256)
        guard digest == reference.digest,
              UInt64(data.count) == reference.byteCount else {
            throw ToolProcessQualificationEvidenceBuildError.artifactIntegrityFailed(
                reference.id.description
            )
        }
        return data
    }
}
