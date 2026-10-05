import CircuiteFoundation
import CircuiteFoundationFoundation
import Foundation
import Testing
import ToolQualification

@Suite("Declared tool execution identity")
struct ToolEnvironmentExecutionIdentityTests {
    @Test func roundTripPreservesPathIndependentProducerAndExistingFields() throws {
        let producer = try ProducerIdentity(
            kind: .tool, identifier: "pex-native", version: "1.0.0",
            build: String(repeating: "a", count: 64)
        )
        let native = ToolEnvironment(platform: "macOS", executionProducer: producer)
        let nativeCopy = try JSONDecoder().decode(
            ToolEnvironment.self, from: JSONEncoder().encode(native)
        )
        #expect(nativeCopy == native)
        #expect(nativeCopy.executablePath == nil)
        #expect(nativeCopy.requiredAssets.isEmpty)
        #expect(nativeCopy.executionProducer == producer)

        let external = ToolEnvironment(
            executablePath: "/tools/pex", libraryPath: "/models",
            platform: "macOS",
            requiredAssets: [ToolAsset(
                path: "/tools/pex", kind: .executable,
                sha256: String(repeating: "a", count: 64)
            )],
            executionProducer: producer
        )
        let externalCopy = try JSONDecoder().decode(
            ToolEnvironment.self, from: JSONEncoder().encode(external)
        )
        #expect(externalCopy == external)
        #expect(externalCopy.isStructurallyValid)
    }

    @Test func currentProducerDistinguishesMissingAndMismatchedRecordIdentity() throws {
        let currentProducer = try ProducerIdentity(
            kind: .tool, identifier: "pex-native", version: "1.0.0", build: "current-build"
        )
        let retainedProducer = try ProducerIdentity(
            kind: .tool, identifier: "pex-native", version: "1.0.0", build: "retained-build"
        )
        let current = ToolEnvironment(platform: "macOS", executionProducer: currentProducer)
        let retained = ToolEnvironment(platform: "macOS", executionProducer: retainedProducer)
        let missing = ToolEnvironment(platform: "macOS")
        #expect(current != retained)
        #expect(current != missing)
        #expect(Set([current, retained, missing]).count == 3)
        let copy = try JSONDecoder().decode(
            ToolEnvironment.self, from: JSONEncoder().encode(current)
        )
        #expect(Set([current, copy]).count == 1)
    }

    @Test func absentProducerRemainsUnknownDespiteExecutableAsset() throws {
        let data = Data("""
        {"executablePath":"/tools/pex","platform":"macOS","requiredAssets":[
          {"path":"/tools/pex","kind":"executable","sha256":"\(String(repeating: "b", count: 64))"}
        ]}
        """.utf8)
        let environment = try JSONDecoder().decode(ToolEnvironment.self, from: data)
        #expect(environment.executionProducer == nil)
        #expect(environment.executablePath == "/tools/pex")
        #expect(environment.requiredAssets.count == 1)
        #expect(environment.isStructurallyValid)
        let copy = try JSONDecoder().decode(
            ToolEnvironment.self, from: JSONEncoder().encode(environment)
        )
        #expect(copy.executionProducer == nil)
        #expect(copy == environment)
    }

    @Test func malformedProducerIsRejectedDuringEnvironmentDecoding() throws {
        let data = Data("""
        {"platform":"macOS","requiredAssets":[],"executionProducer":{
          "kind":"tool","identifier":"pex-native","version":"1.0.0","build":""
        }}
        """.utf8)
        #expect(throws: TokenError.empty(kind: "Producer build")) {
            try JSONDecoder().decode(ToolEnvironment.self, from: data)
        }
    }
}
