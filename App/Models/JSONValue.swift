import Foundation

/// Loose JSON tree. op.gg lists balance changes by dotted path (`ability.desc`,
/// `org.fromDesc`, `stats`, `level`), so payloads have to stay addressable at runtime
/// instead of being pinned to a fixed struct.
indirect enum JSONValue {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null
}

extension JSONValue: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let text = try? container.decode(String.self) {
            self = .string(text)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let flag = try? container.decode(Bool.self) {
            self = .bool(flag)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            self = .null
        }
    }
}

extension JSONValue {
    subscript(key: String) -> JSONValue? {
        guard case .object(let values) = self else { return nil }
        return values[key]
    }

    /// Walks `a.b.c`; returns nil for a missing segment.
    func value(atPath path: String) -> JSONValue? {
        var node = self
        for segment in path.split(separator: ".") {
            guard let next = node[String(segment)] else { return nil }
            node = next
        }
        return node
    }

    var stringValue: String? { if case .string(let value) = self { return value }; return nil }
    var numberValue: Double? { if case .number(let value) = self { return value }; return nil }
    var intValue: Int? { numberValue.map { Int($0) } }
    var boolValue: Bool? { if case .bool(let value) = self { return value }; return nil }
    var arrayValue: [JSONValue] { if case .array(let value) = self { return value }; return [] }
    var objectValue: [String: JSONValue] { if case .object(let value) = self { return value }; return [:] }

    /// First array entry whose `name` matches — how ability variables are keyed.
    func named(_ name: String) -> JSONValue? {
        arrayValue.first { $0["name"]?.stringValue == name }
    }

    /// Display text for any node, trimming the zero padding op.gg pads level arrays with.
    var displayText: String? {
        switch self {
        case .null: return nil
        case .bool(let flag): return flag ? L("App.bool.yes") : L("App.bool.no")
        case .number, .string: return scalarText
        case .array(let values):
            var scalars = values
            while scalars.count > 1, scalars.last?.numberValue == 0 { scalars.removeLast() }
            let parts = scalars.compactMap { $0.scalarText }
            return parts.isEmpty ? nil : parts.joined(separator: " / ")
        case .object: return nil
        }
    }

    private var scalarText: String? {
        switch self {
        case .number(let value):
            return value == value.rounded() ? String(Int(value)) : String(format: "%g", value)
        case .string(let value):
            return value.replacingOccurrences(of: "<br>", with: "\n")
                .replacingOccurrences(of: "<b>", with: "")
                .replacingOccurrences(of: "</b>", with: "")
        case .bool(let flag): return flag ? L("App.bool.yes") : L("App.bool.no")
        default: return nil
        }
    }
}
