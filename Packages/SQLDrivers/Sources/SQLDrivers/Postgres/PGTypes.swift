import Foundation

/// Postgres type OIDs we understand. Everything else degrades to text.
public enum PGTypeID: UInt32, Sendable, CaseIterable {
    case bool = 16
    case bytea = 17
    case char = 18
    case name = 19
    case int8 = 20
    case int2 = 21
    case int4 = 23
    case oid = 26
    case text = 25
    case json = 114
    case xml = 142
    case float4 = 700
    case float8 = 701
    case unknown = 705
    case bpchar = 1042
    case varchar = 1043
    case date = 1082
    case time = 1083
    case timestamp = 1114
    case timestamptz = 1184
    case interval = 1186
    case numeric = 1700
    case uuid = 2950
    case jsonb = 3802

    public var displayName: String {
        switch self {
        case .bool: "bool"
        case .bytea: "bytea"
        case .char: "char"
        case .name: "name"
        case .int8: "int8"
        case .int2: "int2"
        case .int4: "int4"
        case .oid: "oid"
        case .text: "text"
        case .json: "json"
        case .xml: "xml"
        case .float4: "float4"
        case .float8: "float8"
        case .unknown: "text"
        case .bpchar: "bpchar"
        case .varchar: "varchar"
        case .date: "date"
        case .time: "time"
        case .timestamp: "timestamp"
        case .timestamptz: "timestamptz"
        case .interval: "interval"
        case .numeric: "numeric"
        case .uuid: "uuid"
        case .jsonb: "jsonb"
        }
    }
}

public func parsePGValue(text: String, oid: UInt32) -> SQLValue {
    switch PGTypeID(rawValue: oid) {
    case .bool:
        return .bool(text == "t" || text == "true" || text == "1")
    case .int2, .int4, .int8, .oid:
        if let value = Int64(text) {
            return .int(value)
        }
        return .string(text)
    case .float4, .float8:
        if let value = Double(text) {
            return .double(value)
        }
        return .string(text)
    case .bytea:
        if text.hasPrefix("\\x") {
            return .data(hexDecoded(String(text.dropFirst(2))))
        }
        return .string(text)
    case .numeric, .text, .varchar, .bpchar, .char, .name, .json, .jsonb, .xml, .uuid,
         .date, .time, .timestamp, .timestamptz, .interval, .unknown:
        return .string(text)
    case nil:
        return .string(text)
    }
}

private func hexDecoded(_ hex: String) -> Data {
    var data = Data()
    var index = hex.startIndex
    while index < hex.endIndex {
        let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
        if let byte = UInt8(hex[index..<next], radix: 16) {
            data.append(byte)
        }
        index = next
    }
    return data
}
