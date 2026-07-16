import Foundation

enum ToolQualificationCanonicalJSON {
    static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(iso8601String(from: date))
        }
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func decode<Value: Decodable & Encodable & Equatable>(
        _ type: Value.Type,
        from data: Data
    ) throws -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = iso8601Date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "date must use canonical ISO-8601 encoding"
                )
            }
            return date
        }
        let value = try decoder.decode(type, from: data)
        guard try encode(value) == data else {
            throw ToolProcessQualificationEvidenceBuildError.invalidInput(
                "qualification result artifact must use canonical JSON encoding"
            )
        }
        return value
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func iso8601Date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}
