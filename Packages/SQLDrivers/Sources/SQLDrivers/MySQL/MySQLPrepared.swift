import Foundation

enum MySQLPrepared: Sendable {
    static let comQuery: UInt8 = 0x03
    static let comStmtPrepare: UInt8 = 0x16
    static let comStmtExecute: UInt8 = 0x17
    static let comStmtClose: UInt8 = 0x19
    static let comQuit: UInt8 = 0x01

    static func buildExecutePayload(statementID: UInt32, parameters: [SQLValue]) -> Data {
        var data = Data([comStmtExecute])
        data.append(MySQLWire.uint32(statementID))
        data.append(0)
        data.append(contentsOf: [1, 0, 0, 0])
        let bitmapLength = (parameters.count + 7) / 8
        var bitmap = Data(repeating: 0, count: bitmapLength)
        for (index, value) in parameters.enumerated() where value == .null {
            bitmap[bitmap.startIndex + index / 8] |= 1 << (index % 8)
        }
        data.append(bitmap)
        data.append(1)
        for value in parameters {
            let type: UInt8
            switch value {
            case .null: type = MySQLColumnType.null
            case .bool, .int: type = MySQLColumnType.longLong
            case .double: type = MySQLColumnType.double
            case .data: type = MySQLColumnType.blob
            case .string, .date: type = MySQLColumnType.varString
            }
            data.append(type)
            data.append(0)
        }
        for value in parameters {
            switch value {
            case .null: continue
            case .bool(let flag): data.append(MySQLWire.uint64(flag ? 1 : 0))
            case .int(let integer): data.append(MySQLWire.uint64(UInt64(bitPattern: integer)))
            case .double(let double): data.append(MySQLWire.uint64(double.bitPattern))
            case .data(let bytes):
                data.append(MySQLWire.lengthEncoded(bytes))
            case .string(let string):
                data.append(MySQLWire.lengthEncoded(Data(string.utf8)))
            case .date(let date):
                let string = ISO8601DateFormatter().string(from: date)
                data.append(MySQLWire.lengthEncoded(Data(string.utf8)))
            }
        }
        return Data(data.dropFirst())
    }
}
