import AppKit
import Foundation
import UniformTypeIdentifiers
import SQLCore

extension WorkspaceModel {
    private static let sqlContentType = UTType(filenameExtension: "sql") ?? .plainText

    func openQueryFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [Self.sqlContentType, .plainText]
        panel.allowsOtherFileTypes = true
        panel.title = "Open Query"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let sql = try String(contentsOf: url, encoding: .utf8)
            let title = url.deletingPathExtension().lastPathComponent
            _ = newTab(title: title.isEmpty ? url.lastPathComponent : title, sql: sql, titleIsCustom: true, fileURL: url)
        } catch {
            activeError = error.localizedDescription
        }
    }

    func saveActiveQueryFile() {
        guard let tabID = selectedTabID else { return }
        if let url = document.openTabs.first(where: { $0.id == tabID })?.fileURL {
            writeQueryFile(tabID: tabID, to: url)
        } else {
            saveActiveQueryFileAs()
        }
    }

    func saveActiveQueryFileAs() {
        guard let tabID = selectedTabID,
              let tab = document.openTabs.first(where: { $0.id == tabID }) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.sqlContentType]
        panel.canCreateDirectories = true
        panel.title = "Save Query"
        panel.nameFieldStringValue = tab.fileURL?.lastPathComponent ?? "\(tab.title).sql"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        writeQueryFile(tabID: tabID, to: url)
    }

    private func writeQueryFile(tabID: UUID, to url: URL) {
        let sql = tabTexts[tabID] ?? document.openTabs.first(where: { $0.id == tabID })?.sql ?? ""
        do {
            try sql.write(to: url, atomically: true, encoding: .utf8)
            guard let index = document.openTabs.firstIndex(where: { $0.id == tabID }) else { return }
            document.openTabs[index].fileURL = url
            let title = url.deletingPathExtension().lastPathComponent
            if !title.isEmpty {
                document.openTabs[index].title = uniqueTabTitlePreserving(title, tabID: tabID)
                document.openTabs[index].titleIsCustom = true
            }
            saveWorkspace()
        } catch {
            activeError = error.localizedDescription
        }
    }

    private func uniqueTabTitlePreserving(_ base: String, tabID: UUID) -> String {
        let existing = Set(document.openTabs.filter { $0.id != tabID }.map(\.title))
        if !existing.contains(base) { return base }
        var n = 2
        while existing.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }
}
