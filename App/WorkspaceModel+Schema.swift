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
        guard let connection = await connectionManager.connection(for: profile.id) else {
            if selectedConnectionID == profile.id {
                schemaError = "Not connected."
            }
            return
        }
        if busyProfileID != nil {
            if let snap = schemaByProfile[profile.id],
               selectedConnectionID == profile.id || selectedTabConnectionID == profile.id {
                applySchemaSnapshot(profile.id)
            } else if selectedConnectionID == profile.id {
                schemaError = "A query is running. Stop it before refreshing schema."
            }
            return
        }
        isSchemaLoading = true
        schemaError = nil
        defer { isSchemaLoading = false }
        do {
            let objects = try await SchemaBrowser.listObjects(on: connection)
            let valid = Set(objects.map(\.id))
            var columns = schemaByProfile[profile.id]?.columns ?? [:]
            columns = columns.filter { valid.contains($0.key) }
            schemaByProfile[profile.id] = (objects, columns)
            schemaIndexesByID = schemaIndexesByID.filter { valid.contains($0.key) }
            schemaForeignKeysByID = schemaForeignKeysByID.filter { valid.contains($0.key) }
            if selectedConnectionID == profile.id || selectedTabConnectionID == profile.id {
                applySchemaSnapshot(profile.id)
                schemaExpandedIDs = schemaExpandedIDs.intersection(valid)
            }
            if profile.kind == .postgres {
                let schemas = objects.compactMap(\.schema)
                if let sql = SchemaBrowser.searchPathSQL(schemas: schemas) {
                    _ = try? await connection.execute(sql)
                }
            }
            if profile.kind != .redis {
                startColumnPrefetch(prioritize: prioritizedTableNames(), profileID: profile.id)
            }
        } catch {
            if selectedConnectionID == profile.id {
                schemaObjects = []
                schemaTables = []
                schemaError = error.localizedDescription
            }
        }
    }

    var schemaSections: [(schema: String, objects: [SchemaObject])] {
        var order: [String] = []
        var groups: [String: [SchemaObject]] = [:]
        for object in filteredSchemaObjects {
            let key = object.schema?.isEmpty == false ? object.schema! : ""
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(object)
        }
        return order.map { ($0, groups[$0] ?? []) }
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
        if schemaColumnsByID[object.id] == nil
            || (object.kind == .table && schemaIndexesByID[object.id] == nil) {
            Task { await loadSchemaDetails(object) }
        }
    }

    func applySchemaSnapshot(_ profileID: UUID) {
        guard let snap = schemaByProfile[profileID] else { return }
        schemaObjects = snap.objects
        schemaTables = snap.objects.map(\.name)
        schemaColumnsByID = snap.columns
        let valid = Set(snap.objects.map(\.id))
        schemaIndexesByID = schemaIndexesByID.filter { valid.contains($0.key) }
        schemaForeignKeysByID = schemaForeignKeysByID.filter { valid.contains($0.key) }
    }

    func loadSchemaDetails(_ object: SchemaObject, reportError: Bool = true, profileID: UUID? = nil) async {
        await loadSchemaColumns(object, reportError: reportError, profileID: profileID)
        guard object.kind == .table else {
            schemaIndexesByID[object.id] = []
            schemaForeignKeysByID[object.id] = []
            return
        }
        await loadSchemaRelations(object, reportError: reportError, profileID: profileID)
    }

    func loadSchemaRelations(_ object: SchemaObject, reportError: Bool = true, profileID: UUID? = nil) async {
        let id = profileID ?? selectedTabConnectionID ?? selectedConnectionID
        guard let id,
              let connection = await connectionManager.connection(for: id) else { return }
        if busyProfileID != nil { return }
        do {
            let indexes = try await SchemaBrowser.listIndexes(on: connection, object: object)
            let keys = try await SchemaBrowser.listForeignKeys(on: connection, object: object)
            let columns = schemaColumnsByID[object.id]
                ?? schemaByProfile[id]?.columns[object.id]
                ?? []
            if selectedConnectionID == id || selectedTabConnectionID == id {
                schemaIndexesByID[object.id] = SchemaBrowser.ensuringPrimaryIndex(indexes, columns: columns)
                schemaForeignKeysByID[object.id] = keys
            }
        } catch {
            if reportError {
                schemaError = error.localizedDescription
            }
            if schemaIndexesByID[object.id] == nil {
                schemaIndexesByID[object.id] = []
            }
            if schemaForeignKeysByID[object.id] == nil {
                schemaForeignKeysByID[object.id] = []
            }
        }
    }

    func openForeignKey(_ key: SchemaForeignKey) {
        if let object = schemaObjects.first(where: {
            if let schema = key.refSchema, !schema.isEmpty,
               $0.schema?.caseInsensitiveCompare(schema) == .orderedSame,
               $0.name.caseInsensitiveCompare(key.refTable) == .orderedSame {
                return true
            }
            return $0.name.caseInsensitiveCompare(key.refTable) == .orderedSame
                || $0.displayName.caseInsensitiveCompare(key.refTable) == .orderedSame
        }) {
            openSchemaObject(object)
            return
        }
        if let schema = key.refSchema, !schema.isEmpty {
            openSchemaObject(SchemaObject(schema: schema, name: key.refTable, kind: .table))
            return
        }
        openTable(key.refTable)
    }

    func loadSchemaColumns(_ object: SchemaObject, reportError: Bool = true, profileID: UUID? = nil) async {
        let id = profileID ?? selectedTabConnectionID ?? selectedConnectionID
        guard let id,
              let connection = await connectionManager.connection(for: id) else { return }
        if busyProfileID != nil {
            if reportError {
                schemaError = "A query is running. Stop it before loading columns."
            }
            return
        }
        do {
            let columns = try await SchemaBrowser.listColumns(on: connection, object: object)
            if selectedConnectionID == id || selectedTabConnectionID == id {
                schemaColumnsByID[object.id] = columns
            }
            if var snap = schemaByProfile[id] {
                snap.columns[object.id] = columns
                schemaByProfile[id] = snap
            } else {
                schemaByProfile[id] = (schemaObjects, schemaColumnsByID)
            }
        } catch {
            if reportError {
                schemaError = error.localizedDescription
            }
        }
    }

    func startColumnPrefetch(prioritize: [String], profileID: UUID? = nil) {
        schemaPrefetchTask?.cancel()
        let id = profileID ?? selectedTabConnectionID ?? selectedConnectionID
        let objects = id.flatMap { schemaByProfile[$0]?.objects } ?? schemaObjects
        guard !objects.isEmpty else { return }
        let priority = Set(prioritize.map { $0.lowercased() })
        schemaPrefetchTask = Task { [weak self] in
            guard let self else { return }
            let ordered = objects.sorted { lhs, rhs in
                let lp = priority.contains(lhs.name.lowercased())
                let rp = priority.contains(rhs.name.lowercased())
                if lp != rp { return lp && !rp }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            for object in ordered {
                if Task.isCancelled { return }
                if self.busyProfileID != nil { return }
                let cached = id.flatMap { self.schemaByProfile[$0]?.columns[object.id] }
                if cached != nil || self.schemaColumnsByID[object.id] != nil { continue }
                await self.loadSchemaColumns(object, reportError: false, profileID: id)
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    func ensureCompletionColumns(named raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let profileID = selectedTabConnectionID ?? selectedConnectionID
        let objects = profileID.flatMap { schemaByProfile[$0]?.objects } ?? schemaObjects
        let columns = profileID.flatMap { schemaByProfile[$0]?.columns } ?? schemaColumnsByID
        guard let object = objects.first(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
                || $0.displayName.caseInsensitiveCompare(name) == .orderedSame
        }) else { return }
        if columns[object.id] != nil { return }
        Task {
            await loadSchemaColumns(object, reportError: false, profileID: profileID)
            refreshEditorCompletion?()
        }
    }

    func refreshSchema(for profileID: UUID) {
        guard let profile = document.connections.first(where: { $0.id == profileID }) else { return }
        Task { await loadSchema(for: profile) }
    }

    func selectEditorTab(_ tabID: UUID) {
        selectedTabID = tabID
        guard let profileID = document.openTabs.first(where: { $0.id == tabID })?.connectionProfileID else { return }
        selectedConnectionID = profileID
        applySchemaSnapshot(profileID)
        if schemaByProfile[profileID] == nil,
           status(for: profileID) == .connected,
           let profile = document.connections.first(where: { $0.id == profileID }) {
            Task { await loadSchema(for: profile) }
        }
    }

    func prioritizedTableNames() -> [String] {
        let sql = selectedTabID.flatMap { tabTexts[$0] } ?? ""
        return SQLLexer().tokenize(sql).compactMap { token in
            token.kind == .identifier ? token.text : nil
        }
    }

    func completionCatalog() -> SQLCompletionCatalog {
        let profileID = selectedTabConnectionID ?? selectedConnectionID
        let kind = profileID.flatMap { id in
            document.connections.first(where: { $0.id == id })?.kind
        } ?? .postgres
        let snap = profileID.flatMap { schemaByProfile[$0] }
        let liveObjects = snap?.objects ?? schemaObjects
        let liveColumns = snap?.columns ?? schemaColumnsByID
        var objects = liveObjects.map { object in
            let columns = (liveColumns[object.id] ?? []).map { column in
                SQLCompletionColumn(
                    name: column.name,
                    insertText: quoteIfNeeded(column.name, kind: kind),
                    detail: column.dataType.isEmpty ? nil : column.dataType,
                    tableName: object.name
                )
            }
            let tableInsert = quoteIfNeeded(object.name, kind: kind)
            let qualifiedInsert: String
            if let schema = object.schema, !schema.isEmpty {
                qualifiedInsert = quoteIfNeeded(schema, kind: kind) + "." + tableInsert
            } else {
                qualifiedInsert = tableInsert
            }
            return SQLCompletionObject(
                name: object.name,
                insertText: qualifiedInsert,
                kind: object.kind == .view ? .view : .table,
                columns: columns,
                schema: object.schema
            )
        }
        let sql = selectedTabID.flatMap { tabTexts[$0] } ?? ""
        for declared in SQLCompletionEngine.objectsDeclared(in: sql) {
            if let index = objects.firstIndex(where: { $0.name.caseInsensitiveCompare(declared.name) == .orderedSame }) {
                var merged = objects[index].columns
                for column in declared.columns where !merged.contains(where: { $0.name.caseInsensitiveCompare(column.name) == .orderedSame }) {
                    merged.append(
                        SQLCompletionColumn(
                            name: column.name,
                            insertText: quoteIfNeeded(column.name, kind: kind),
                            tableName: declared.name
                        )
                    )
                }
                objects[index].columns = merged
            } else {
                objects.append(
                    SQLCompletionObject(
                        name: declared.name,
                        insertText: quoteIfNeeded(declared.name, kind: kind),
                        kind: .table,
                        columns: declared.columns.map {
                            SQLCompletionColumn(
                                name: $0.name,
                                insertText: quoteIfNeeded($0.name, kind: kind),
                                tableName: declared.name
                            )
                        }
                    )
                )
            }
        }
        return SQLCompletionCatalog(objects: objects)
    }

    private func quoteIfNeeded(_ name: String, kind: DatabaseKind) -> String {
        guard SQLCompletionEngine.needsQuoting(name) else { return name }
        return SchemaBrowser.quoteIdentifier(name, kind: kind)
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
