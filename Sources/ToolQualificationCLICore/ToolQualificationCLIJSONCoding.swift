import Foundation

/// Shared JSON file decoding and result-envelope encoding for CLI commands.
enum ToolQualificationCLIJSONCoding {
    static func decode<Model: Decodable>(_ type: Model.Type, atPath path: String) throws -> Model {
        let data: Data
        do {
            data = try Data(contentsOf: URL(filePath: path))
        } catch {
            throw ToolQualificationCLIError.unreadableFile(
                path: path,
                reason: error.localizedDescription
            )
        }
        do {
            return try JSONDecoder().decode(Model.self, from: data)
        } catch let decodingError as DecodingError {
            throw ToolQualificationCLIError.invalidJSON(
                path: path,
                reason: describe(decodingError)
            )
        } catch {
            throw ToolQualificationCLIError.invalidJSON(
                path: path,
                reason: error.localizedDescription
            )
        }
    }

    static func encode<Envelope: Encodable>(_ envelope: Envelope, pretty: Bool) throws -> String {
        let encoder = JSONEncoder()
        var formatting: JSONEncoder.OutputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if pretty {
            formatting.insert(.prettyPrinted)
        }
        encoder.outputFormatting = formatting
        do {
            let data = try encoder.encode(envelope)
            return String(decoding: data, as: UTF8.self)
        } catch {
            throw ToolQualificationCLIError.internalError(
                "Failed to encode result envelope: \(error)"
            )
        }
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            "missing key '\(key.stringValue)' at \(path(context))"
        case .typeMismatch(_, let context):
            "type mismatch at \(path(context)): \(context.debugDescription)"
        case .valueNotFound(_, let context):
            "missing value at \(path(context)): \(context.debugDescription)"
        case .dataCorrupted(let context):
            "corrupted data at \(path(context)): \(context.debugDescription)"
        @unknown default:
            String(describing: error)
        }
    }

    private static func path(_ context: DecodingError.Context) -> String {
        let joined = context.codingPath.map(\.stringValue).joined(separator: ".")
        return joined.isEmpty ? "<root>" : joined
    }
}
