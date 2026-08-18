import Foundation
import SQLImportExport

@MainActor
@Observable
final class ImportSession: Identifiable {
    let id = UUID()
    var profileID: UUID?
    var rawData: Data
    var dialect: CSVDialect
    var csvColumns: [String] = []
    var csvRows: [[String]] = []
    var hasHeader = true
    var targetTable = ""
    var tableColumns: [String] = []
    var mapping: [String: String] = [:]
    var isRunning = false
    var inserted = 0
    var failed = 0
    var errorMessage: String?

    init(rawData: Data, dialect: CSVDialect, hasHeader: Bool) throws {
        self.rawData = rawData
        self.dialect = dialect
        self.hasHeader = hasHeader
        try applyParse()
    }

    convenience init(csvColumns: [String], csvRows: [[String]], hasHeader: Bool) {
        self.init(
            rawData: Data(),
            dialect: .csv,
            csvColumns: csvColumns,
            csvRows: csvRows,
            hasHeader: hasHeader
        )
    }

    private init(
        rawData: Data,
        dialect: CSVDialect,
        csvColumns: [String],
        csvRows: [[String]],
        hasHeader: Bool
    ) {
        self.rawData = rawData
        self.dialect = dialect
        self.csvColumns = csvColumns
        self.csvRows = csvRows
        self.hasHeader = hasHeader
    }

    func applyParse() throws {
        let text = CSVCodec.decode(rawData, encoding: dialect.encoding)
            ?? String(decoding: rawData, as: UTF8.self)
        let parsed = try CSVCodec.parse(text, dialect: dialect)
        applyParsedRows(parsed)
    }

    func applyParsedRows(_ parsed: [[String]]) {
        guard let first = parsed.first, !first.isEmpty else {
            csvColumns = []
            csvRows = []
            return
        }
        if hasHeader {
            csvColumns = first
            csvRows = Array(parsed.dropFirst())
        } else {
            csvColumns = first.indices.map { "col_\($0 + 1)" }
            csvRows = parsed
        }
        mapping = mapping.filter { csvColumns.contains($0.value) }
        autoMap()
    }

    func autoMap() {
        for tableColumn in tableColumns {
            if mapping[tableColumn] == nil, csvColumns.contains(tableColumn) {
                mapping[tableColumn] = tableColumn
            }
        }
    }

    var previewRows: [[String]] {
        Array(csvRows.prefix(5))
    }

    var delimiterKind: CSVDelimiterKind {
        get { CSVDelimiterKind.from(dialect.delimiter) }
        set {
            dialect.delimiter = newValue.character
            try? applyParse()
        }
    }

    var quoteIsApostrophe: Bool {
        get { dialect.quote == "'" }
        set {
            dialect.quote = newValue ? "'" : "\""
            try? applyParse()
        }
    }

    var textEncoding: CSVTextEncoding {
        get { CSVTextEncoding.from(dialect.encoding) }
        set {
            dialect.encoding = newValue.encoding
            try? applyParse()
        }
    }
}
