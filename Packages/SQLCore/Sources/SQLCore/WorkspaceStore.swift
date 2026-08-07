import Foundation

public enum WorkspaceStoreError: Error, Sendable {
    case noSuchFile
}

public struct WorkspaceStore: Sendable {
    private static let fileName = "Workspace.json"
    private static let appDirectoryName = "SexiQL"

    public let baseDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(baseDirectory: URL? = nil) {
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.baseDirectory = support.appendingPathComponent(Self.appDirectoryName, isDirectory: true)
        }
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    public var fileURL: URL { baseDirectory.appendingPathComponent(Self.fileName) }

    public func load() throws -> WorkspaceDocument? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(WorkspaceDocument.self, from: data)
    }

    public func save(_ document: WorkspaceDocument) throws {
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let data = try encoder.encode(document)
        try data.write(to: fileURL, options: .atomic)
    }

    public func delete() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { throw WorkspaceStoreError.noSuchFile }
        try FileManager.default.removeItem(at: fileURL)
    }
}
