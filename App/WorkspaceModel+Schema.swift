import AppKit
import Foundation
import SQLCore
import SQLDrivers
import SQLGrid
import SQLEditor
import SQLImportExport
import SQLExplainer

extension WorkspaceModel {
    // MARK: - Schema browsing

    func loadSchema(for profile: ConnectionProfile) async {
        guard let connection = await connectionManager.connection(for: profile.id) else { return }
        if busyProfileID != nil {
            schemaError = "A query is running. Stop it before refreshing schema."
            return
        }
        isSchemaLoading = true
        schemaError = nil
        defer { isSchemaLoading = false }
        do {
            let objects = try await SchemaBrowser.listObjects(on: connection)
            schemaObjects = objects
            schemaTables = objects.map(\.name)
            let valid = Set(objects.map(\.id))
            schemaColumnsByID = schemaColumnsByID.filter { valid.contains($0.key) }
            schemaExpandedIDs = schemaExpandedIDs.intersection(valid)
        } catch {
            schemaObjects = []
            schemaTables = []
            schemaError = error.localizedDescription
        }
    }

    func refreshSchema() {
        guard let id = selectedConnectionID,
              let profile = document.connections.first(where: { $0.id == id }) else { return }
        Task { await loadSchema(for: profile) }
    }

    var filteredSchemaObjects: [SchemaObject] {
        let q = schemaFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return schemaObjects }
        return schemaObjects.filter {
            $0.displayName.localizedCaseInsensitiveContains(q)
                || $0.name.localizedCaseInsensitiveContains(q)
        }
    }

    func toggleSchemaExpand(_ object: SchemaObject) {
        if schemaExpandedIDs.contains(object.id) {
            schemaExpandedIDs.remove(object.id)
            return
        }
        schemaExpandedIDs.insert(object.id)
        if schemaColumnsByID[object.id] == nil {
            Task { await loadSchemaColumns(object) }
        }
    }

    func loadSchemaColumns(_ object: SchemaObject) async {
        guard let id = selectedConnectionID,
              let connection = await connectionManager.connection(for: id) else { return }
        if busyProfileID != nil {
            schemaError = "A query is running. Stop it before loading columns."
            return
        }
        do {
            let columns = try await SchemaBrowser.listColumns(on: connection, object: object)
            schemaColumnsByID[object.id] = columns
        } catch {
            schemaError = error.localizedDescription
        }
    }

    func openTable(_ name: String) {
        if let object = schemaObjects.first(where: { $0.name == name || $0.displayName == name }) {
            openSchemaObject(object)
            return
        }
        guard let profile = selectedConnectionID.flatMap({ id in
            document.connections.first(where: { $0.id == id })
        }) else { return }
        let object = SchemaObject(schema: nil, name: name, kind: .table)
        let sql = SchemaBrowser.selectAllSQL(object, kind: profile.kind)
        let tab = newTab(title: name, sql: sql, titleIsCustom: true)
        run(tab.id)
    }

    func openSchemaObject(_ object: SchemaObject) {
        guard let profile = selectedConnectionID.flatMap({ id in
            document.connections.first(where: { $0.id == id })
        }) else {
            activeError = "Select a connection first."
            return
        }
        if busyProfileID != nil {
            activeError = "A query is running. Stop it before opening a table."
            return
        }
        let sql = SchemaBrowser.selectAllSQL(object, kind: profile.kind)
        let tab = newTab(title: object.name, sql: sql, titleIsCustom: true)
        run(tab.id)
    }

}
