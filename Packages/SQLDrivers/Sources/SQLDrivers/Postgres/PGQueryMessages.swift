import Foundation

enum PGQueryMessages: Sendable {
    static func simpleQueryPayload(_ sql: String) -> Data {
        PGWire.cstring(sql)
    }

    struct ExtendedQueryPayloads: Sendable {
        var parse: Data
        var bind: Data
        var describe: Data
        var execute: Data
        var sync: Data
    }

    static func extendedQuery(sql: String, parameters: [SQLValue]) -> ExtendedQueryPayloads {
        var parse = PGWire.cstring("")
        parse.append(PGWire.cstring(sql))
        parse.append(PGWire.int16(0))

        var bind = PGWire.cstring("")
        bind.append(PGWire.cstring(""))
        bind.append(PGWire.int16(0))
        bind.append(PGWire.int16(Int16(parameters.count)))
        for value in parameters {
            if value == .null {
                bind.append(PGWire.int32(-1))
            } else {
                let text = PGRowCodec.textEncoding(value)
                bind.append(PGWire.int32(Int32(text.utf8.count)))
                bind.append(Data(text.utf8))
            }
        }
        bind.append(PGWire.int16(0))

        var describe = Data()
        describe.append(0x50)
        describe.append(PGWire.cstring(""))

        var execute = PGWire.cstring("")
        execute.append(PGWire.int32(0))

        return ExtendedQueryPayloads(
            parse: parse,
            bind: bind,
            describe: describe,
            execute: execute,
            sync: Data()
        )
    }
}
