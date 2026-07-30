import Foundation

enum PersistenceError: Error, Equatable {
    case unsupportedSchema(Int)
}

protocol ResearchPersistence: Sendable {
    func load() throws -> ResearchState?
    func save(_ state: ResearchState) throws
}

struct PreferenceSyncState: Codable, Equatable, Sendable {
    let pendingPatch: ServerPreferencePatch
    let etag: String?
    let idempotencyKey: String?

    init(pendingPatch: ServerPreferencePatch, etag: String?, idempotencyKey: String? = nil) {
        self.pendingPatch = pendingPatch
        self.etag = etag
        self.idempotencyKey = idempotencyKey
    }
}

protocol PreferenceSyncStatePersistence: Sendable {
    func loadPreferenceSyncState() throws -> PreferenceSyncState?
    func savePreferenceSyncState(_ state: PreferenceSyncState) throws
}

struct PersistenceDocument: Codable, Sendable {
    static let currentSchemaVersion = 4

    let schemaVersion: Int
    let savedAt: Date
    let state: ResearchState
}

struct JSONResearchPersistence: ResearchPersistence, PreferenceSyncStatePersistence, Sendable {
    let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL) {
        self.fileURL = fileURL
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    static func production(fileManager: FileManager = .default) -> JSONResearchPersistence {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return JSONResearchPersistence(
            fileURL: base
                .appendingPathComponent("Zoid99", isDirectory: true)
                .appendingPathComponent("research-state.json")
        )
    }

    func load() throws -> ResearchState? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let version = try decoder.decode(SchemaHeader.self, from: data).schemaVersion
        switch version {
        case PersistenceDocument.currentSchemaVersion, 3, 2:
            return try decoder.decode(PersistenceDocument.self, from: data).state
        case 1:
            return try migrateV1(decoder.decode(PersistenceDocumentV1.self, from: data))
        default:
            throw PersistenceError.unsupportedSchema(version)
        }
    }

    func save(_ state: ResearchState) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let document = PersistenceDocument(
            schemaVersion: PersistenceDocument.currentSchemaVersion,
            savedAt: .now,
            state: state
        )
        let data = try encoder.encode(document)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    func loadPreferenceSyncState() throws -> PreferenceSyncState? {
        let url = preferenceSyncFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decoder.decode(PreferenceSyncState.self, from: Data(contentsOf: url))
    }

    func savePreferenceSyncState(_ state: PreferenceSyncState) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(state)
        try data.write(to: preferenceSyncFileURL, options: [.atomic, .completeFileProtection])
    }

    private var preferenceSyncFileURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("preferences-sync.json")
    }

    private func migrateV1(_ document: PersistenceDocumentV1) -> ResearchState {
        ResearchState(
            sourceItems: document.sourceItems,
            opportunities: document.opportunities,
            comments: document.comments,
            dispositions: document.dispositions,
            watchlist: document.watchlist,
            settings: document.settings,
            notificationHistory: document.notificationHistory,
            sourceHealth: document.sourceHealth,
            sourceHealthHistory: [],
            lastSuccessfulSyncAt: nil,
            watchlistNeedsSync: !document.watchlist.isEmpty
        )
    }
}

private struct SchemaHeader: Decodable {
    let schemaVersion: Int
}

struct PersistenceDocumentV1: Codable {
    let schemaVersion: Int
    let sourceItems: [SourceItem]
    let opportunities: [Opportunity]
    let comments: [CommentCluster]
    let dispositions: [UUID: OpportunityDisposition]
    let watchlist: [WatchlistEntry]
    let settings: AppSettings
    let notificationHistory: [NotificationRecord]
    let sourceHealth: [SourceHealth]
}
