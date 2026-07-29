import Foundation

struct SourceSyncResult: Sendable {
    let group: SourceGroup
    let collectedAt: Date
    let items: [SourceItem]
    let state: ConnectionState
    let dataTruth: DataTruth
    let evidence: String
    var canonicalOpportunities: [Opportunity]? = nil
    var canonicalNotifications: [NotificationRecord]? = nil
}

struct ResearchSyncSeed: Sendable {
    let sourceItems: [SourceItem]
    let opportunities: [Opportunity]
    let sourceHealth: [SourceHealth]
    let notifications: [NotificationRecord]
    let sourceBlocklist: [SourceBlockRule]

    init(
        sourceItems: [SourceItem],
        opportunities: [Opportunity] = [],
        sourceHealth: [SourceHealth],
        notifications: [NotificationRecord],
        sourceBlocklist: [SourceBlockRule]
    ) {
        self.sourceItems = sourceItems
        self.opportunities = opportunities
        self.sourceHealth = sourceHealth
        self.notifications = notifications
        self.sourceBlocklist = sourceBlocklist
    }
}

protocol ResearchSyncing: Sendable {
    func synchronize() async -> [SourceSyncResult]
    func synchronize(watchlist: [WatchlistEntry]) async -> [SourceSyncResult]
    func synchronize(watchlist: [WatchlistEntry], seed: ResearchSyncSeed) async -> [SourceSyncResult]
    func researchTopic(_ query: String, watchlist: [WatchlistEntry]) async -> [SourceSyncResult]
}

extension ResearchSyncing {
    func synchronize(watchlist: [WatchlistEntry]) async -> [SourceSyncResult] {
        await synchronize()
    }

    func synchronize(watchlist: [WatchlistEntry], seed: ResearchSyncSeed) async -> [SourceSyncResult] {
        await synchronize(watchlist: watchlist)
    }

    func researchTopic(_ query: String, watchlist: [WatchlistEntry]) async -> [SourceSyncResult] {
        var queryWatchlist = watchlist
        if !queryWatchlist.contains(where: {
            $0.kind == .topic && $0.value.caseInsensitiveCompare(query) == .orderedSame
        }) {
            queryWatchlist.append(
                WatchlistEntry(id: UUID(), kind: .topic, value: query, highPriority: true)
            )
        }
        return await synchronize(watchlist: queryWatchlist)
    }
}

struct WatchlistSyncResult: Sendable {
    let synchronizedEntries: [WatchlistEntry]
    let errorMessage: String?
}

struct ServerQuietHours: Codable, Equatable, Sendable {
    let enabled: Bool
    let start: String
    let end: String
}

struct ServerPreferences: Codable, Equatable, Sendable {
    let refreshMinutes: Int
    let notificationsEnabled: Bool
    let digestHour: Int
    let quietHours: ServerQuietHours
    let locale: String
    let timeZone: String
    let updatedAt: Date
}

struct ServerPreferencePatch: Codable, Equatable, Sendable {
    var refreshMinutes: Int?
    var notificationsEnabled: Bool?
    var digestHour: Int?
    var quietHours: ServerQuietHours?
    var locale: String?
    var timeZone: String?

    init(
        refreshMinutes: Int? = nil,
        notificationsEnabled: Bool? = nil,
        digestHour: Int? = nil,
        quietHours: ServerQuietHours? = nil,
        locale: String? = nil,
        timeZone: String? = nil
    ) {
        self.refreshMinutes = refreshMinutes
        self.notificationsEnabled = notificationsEnabled
        self.digestHour = digestHour
        self.quietHours = quietHours
        self.locale = locale
        self.timeZone = timeZone
    }

    var isEmpty: Bool {
        refreshMinutes == nil
            && notificationsEnabled == nil
            && digestHour == nil
            && quietHours == nil
            && locale == nil
            && timeZone == nil
    }

    func merging(_ other: ServerPreferencePatch) -> ServerPreferencePatch {
        ServerPreferencePatch(
            refreshMinutes: other.refreshMinutes ?? refreshMinutes,
            notificationsEnabled: other.notificationsEnabled ?? notificationsEnabled,
            digestHour: other.digestHour ?? digestHour,
            quietHours: other.quietHours ?? quietHours,
            locale: other.locale ?? locale,
            timeZone: other.timeZone ?? timeZone
        )
    }

    func removing(_ sent: ServerPreferencePatch) -> ServerPreferencePatch {
        ServerPreferencePatch(
            refreshMinutes: refreshMinutes == sent.refreshMinutes ? nil : refreshMinutes,
            notificationsEnabled: notificationsEnabled == sent.notificationsEnabled ? nil : notificationsEnabled,
            digestHour: digestHour == sent.digestHour ? nil : digestHour,
            quietHours: quietHours == sent.quietHours ? nil : quietHours,
            locale: locale == sent.locale ? nil : locale,
            timeZone: timeZone == sent.timeZone ? nil : timeZone
        )
    }
}

struct PreferenceSyncResult: Sendable {
    let preferences: ServerPreferences?
    let etag: String?
    let conflict: Bool
    let errorMessage: String?
}

protocol PreferenceSyncing: Sendable {
    func fetchCanonical() async -> PreferenceSyncResult
    func update(
        _ patch: ServerPreferencePatch,
        ifMatch etag: String,
        idempotencyKey: String
    ) async -> PreferenceSyncResult
}

struct NoopPreferenceSync: PreferenceSyncing {
    func fetchCanonical() async -> PreferenceSyncResult {
        PreferenceSyncResult(preferences: nil, etag: nil, conflict: false, errorMessage: "Backend preference sync is not configured")
    }

    func update(
        _ patch: ServerPreferencePatch,
        ifMatch etag: String,
        idempotencyKey: String
    ) async -> PreferenceSyncResult {
        PreferenceSyncResult(preferences: nil, etag: nil, conflict: false, errorMessage: patch.isEmpty ? nil : "Backend preference sync is not configured")
    }
}

enum PreferenceSyncFactory {
    static func production(environment: [String: String] = ProcessInfo.processInfo.environment)
        -> any PreferenceSyncing {
        guard let rawURL = environment["ZOID99_API_BASE_URL"] ?? environment["ZOID99_BACKEND_URL"],
              let baseURL = URL(string: rawURL),
              let apiToken = environment["ZOID99_API_TOKEN"],
              apiToken.count >= 32 else {
            return NoopPreferenceSync()
        }
        return BackendPreferenceSync(baseURL: baseURL, apiToken: apiToken)
    }
}

struct BackendPreferenceSync: PreferenceSyncing {
    let baseURL: URL
    let apiToken: String
    let transport: any HTTPTransport

    init(baseURL: URL, apiToken: String, transport: any HTTPTransport = URLSessionHTTPTransport()) {
        self.baseURL = baseURL
        self.apiToken = apiToken
        self.transport = transport
    }

    func fetchCanonical() async -> PreferenceSyncResult {
        await request(method: "GET", body: nil, ifMatch: nil)
    }

    func update(
        _ patch: ServerPreferencePatch,
        ifMatch etag: String,
        idempotencyKey: String
    ) async -> PreferenceSyncResult {
        guard !patch.isEmpty, let body = try? Self.encoder.encode(patch) else {
            return PreferenceSyncResult(preferences: nil, etag: nil, conflict: false, errorMessage: "Backend preference sync failed")
        }
        return await request(method: "PATCH", body: body, ifMatch: etag, idempotencyKey: idempotencyKey)
    }

    private func request(
        method: String,
        body: Data?,
        ifMatch: String?,
        idempotencyKey: String? = nil
    ) async -> PreferenceSyncResult {
        do {
            let response = try await transport.send(
                HTTPRequest(
                    url: baseURL.appendingPathComponent("v1/preferences"),
                    method: method,
                    headers: authorizedHeaders(ifMatch: ifMatch, idempotencyKey: idempotencyKey),
                    body: body
                )
            )
            let decoder = Self.decoder
            if response.statusCode == 409 {
                let conflict = try decoder.decode(PreferenceConflictResponse.self, from: response.body)
                return PreferenceSyncResult(
                    preferences: conflict.preferences,
                    etag: response.header("ETag"),
                    conflict: true,
                    errorMessage: "Backend preference sync conflict"
                )
            }
            guard response.statusCode == 200 else { throw BackendSyncError.httpStatus(response.statusCode) }
            return PreferenceSyncResult(
                preferences: try decoder.decode(ServerPreferences.self, from: response.body),
                etag: response.header("ETag"),
                conflict: false,
                errorMessage: nil
            )
        } catch {
            return PreferenceSyncResult(preferences: nil, etag: nil, conflict: false, errorMessage: "Backend preference sync failed")
        }
    }

    private func authorizedHeaders(ifMatch: String?, idempotencyKey: String?) -> [String: String] {
        var headers = [
            "Accept": "application/json",
            "Authorization": "Bearer \(apiToken)",
            "Content-Type": "application/json"
        ]
        if let ifMatch { headers["If-Match"] = ifMatch }
        headers["Idempotency-Key"] = idempotencyKey
        return headers
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private struct PreferenceConflictResponse: Decodable {
    let preferences: ServerPreferences
}

protocol WatchlistSyncing: Sendable {
    func fetchCanonical() async -> WatchlistSyncResult
    func reconcile(_ entries: [WatchlistEntry]) async -> WatchlistSyncResult
}

extension WatchlistSyncing {
    func fetchCanonical() async -> WatchlistSyncResult {
        WatchlistSyncResult(
            synchronizedEntries: [],
            errorMessage: "Backend watchlist sync is not configured"
        )
    }
}

struct NoopWatchlistSync: WatchlistSyncing {
    func reconcile(_ entries: [WatchlistEntry]) async -> WatchlistSyncResult {
        WatchlistSyncResult(
            synchronizedEntries: [],
            errorMessage: "Backend watchlist sync is not configured"
        )
    }
}

enum WatchlistSyncFactory {
    static func production(environment: [String: String] = ProcessInfo.processInfo.environment)
        -> any WatchlistSyncing {
        guard let rawURL = environment["ZOID99_API_BASE_URL"] ?? environment["ZOID99_BACKEND_URL"],
              let baseURL = URL(string: rawURL),
              let apiToken = environment["ZOID99_API_TOKEN"],
              apiToken.count >= 32 else {
            return NoopWatchlistSync()
        }
        return BackendWatchlistSync(baseURL: baseURL, apiToken: apiToken)
    }
}

struct BackendWatchlistSync: WatchlistSyncing {
    let baseURL: URL
    let apiToken: String
    let transport: any HTTPTransport

    init(baseURL: URL, apiToken: String, transport: any HTTPTransport = URLSessionHTTPTransport()) {
        self.baseURL = baseURL
        self.apiToken = apiToken
        self.transport = transport
    }

    func fetchCanonical() async -> WatchlistSyncResult {
        await request(method: "GET", body: nil)
    }

    func reconcile(_ entries: [WatchlistEntry]) async -> WatchlistSyncResult {
        await request(
            method: "PUT",
            body: try? Self.encoder.encode(ReplacementPayload(entries: entries))
        )
    }

    private func request(method: String, body: Data?) async -> WatchlistSyncResult {
        do {
            guard method == "GET" || body != nil else {
                throw BackendSyncError.invalidResponse
            }
            let response = try await transport.send(
                HTTPRequest(
                    url: baseURL.appendingPathComponent("v1/watchlist"),
                    method: method,
                    headers: [
                        "Accept": "application/json",
                        "Authorization": "Bearer \(apiToken)",
                        "Content-Type": "application/json"
                    ],
                    body: body
                )
            )
            guard response.statusCode == 200 else {
                throw BackendSyncError.httpStatus(response.statusCode)
            }
            return WatchlistSyncResult(
                synchronizedEntries: try Self.decoder.decode([WatchlistEntry].self, from: response.body),
                errorMessage: nil
            )
        } catch {
            return WatchlistSyncResult(
                synchronizedEntries: [],
                errorMessage: "Backend watchlist sync failed"
            )
        }
    }

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private struct ReplacementPayload: Encodable {
        let entries: [WatchlistEntry]
    }
}

struct DispositionSyncResult: Sendable {
    let states: [OpportunityDispositionState]
    let acknowledgedMutationIDs: Set<UUID>
    let errorMessage: String?
}

protocol OpportunityDispositionSyncing: Sendable {
    func reconcile(_ pending: [OpportunityDispositionMutation]) async -> DispositionSyncResult
}

struct NoopOpportunityDispositionSync: OpportunityDispositionSyncing {
    func reconcile(_ pending: [OpportunityDispositionMutation]) async -> DispositionSyncResult {
        DispositionSyncResult(
            states: [],
            acknowledgedMutationIDs: [],
            errorMessage: pending.isEmpty ? nil : "Backend sync is not configured"
        )
    }
}

enum OpportunityDispositionSyncFactory {
    static func production(environment: [String: String] = ProcessInfo.processInfo.environment)
        -> any OpportunityDispositionSyncing {
        guard let rawURL = environment["ZOID99_API_BASE_URL"] ?? environment["ZOID99_BACKEND_URL"],
              let baseURL = URL(string: rawURL),
              let apiToken = environment["ZOID99_API_TOKEN"],
              apiToken.count >= 32 else {
            return NoopOpportunityDispositionSync()
        }
        return BackendOpportunityDispositionSync(baseURL: baseURL, apiToken: apiToken)
    }
}

struct BackendOpportunityDispositionSync: OpportunityDispositionSyncing {
    let baseURL: URL
    let apiToken: String
    let transport: any HTTPTransport

    init(baseURL: URL, apiToken: String, transport: any HTTPTransport = URLSessionHTTPTransport()) {
        self.baseURL = baseURL
        self.apiToken = apiToken
        self.transport = transport
    }

    func reconcile(_ pending: [OpportunityDispositionMutation]) async -> DispositionSyncResult {
        var acknowledged = Set<UUID>()
        var states: [OpportunityDispositionState] = []
        do {
            for mutation in pending.sorted(by: mutationOrder) {
                let body = try Self.encoder.encode(DispositionRequest(mutation))
                let response = try await transport.send(
                    HTTPRequest(
                        url: baseURL
                            .appendingPathComponent("v1/opportunities")
                            .appendingPathComponent(mutation.opportunityID.uuidString)
                            .appendingPathComponent("disposition"),
                        method: "PATCH",
                        headers: authorizedHeaders,
                        body: body
                    )
                )
                guard response.statusCode == 200 else {
                    throw BackendSyncError.httpStatus(response.statusCode)
                }
                let state = try Self.decoder.decode(OpportunityDispositionState.self, from: response.body)
                acknowledged.insert(mutation.id)
                states.append(state)
            }
            states.append(contentsOf: try await fetchCanonicalStates())
            return DispositionSyncResult(
                states: states,
                acknowledgedMutationIDs: acknowledged,
                errorMessage: nil
            )
        } catch {
            return DispositionSyncResult(
                states: states,
                acknowledgedMutationIDs: acknowledged,
                errorMessage: "Backend disposition sync failed"
            )
        }
    }

    private func fetchCanonicalStates() async throws -> [OpportunityDispositionState] {
        var cursor: String?
        var previousCursor: String?
        var remote: [RemoteDisposition] = []

        for _ in 0..<100 {
            var components = URLComponents(
                url: baseURL.appendingPathComponent("v1/opportunities"),
                resolvingAgainstBaseURL: false
            )!
            components.queryItems = [
                URLQueryItem(name: "limit", value: "200"),
                URLQueryItem(name: "sort", value: "newest")
            ]
            if let cursor { components.queryItems?.append(URLQueryItem(name: "cursor", value: cursor)) }
            let response = try await transport.send(
                HTTPRequest(url: components.url!, headers: authorizedHeaders)
            )
            if response.statusCode == 400, cursor == nil {
                let legacyResponse = try await transport.send(
                    HTTPRequest(
                        url: baseURL.appendingPathComponent("v1/opportunities"),
                        headers: authorizedHeaders
                    )
                )
                guard legacyResponse.statusCode == 200 else {
                    throw BackendSyncError.httpStatus(legacyResponse.statusCode)
                }
                return try Self.decoder.decode([RemoteDisposition].self, from: legacyResponse.body).map(\.state)
            }
            guard response.statusCode == 200 else {
                throw BackendSyncError.httpStatus(response.statusCode)
            }
            let page = try Self.decoder.decodeReadPage(RemoteDisposition.self, from: response.body)
            remote.append(contentsOf: page.items)
            guard let nextCursor = page.nextCursor else { return remote.map(\.state) }
            guard nextCursor != cursor, nextCursor != previousCursor else {
                throw BackendSyncError.invalidResponse
            }
            previousCursor = cursor
            cursor = nextCursor
        }
        throw BackendSyncError.invalidResponse
    }

    private var authorizedHeaders: [String: String] {
        [
            "Accept": "application/json",
            "Authorization": "Bearer \(apiToken)",
            "Content-Type": "application/json"
        ]
    }

    private func mutationOrder(_ left: OpportunityDispositionMutation, _ right: OpportunityDispositionMutation) -> Bool {
        if left.changedAt != right.changedAt { return left.changedAt < right.changedAt }
        return left.id.uuidString < right.id.uuidString
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private struct PaginatedReadPage<Item: Decodable>: Decodable {
    let items: [Item]
    let nextCursor: String?
}

private extension JSONDecoder {
    func decodeReadPage<Item: Decodable>(_ type: Item.Type, from data: Data) throws -> PaginatedReadPage<Item> {
        if let page = try? decode(PaginatedReadPage<Item>.self, from: data) { return page }
        return PaginatedReadPage(items: try decode([Item].self, from: data), nextCursor: nil)
    }
}

private struct DispositionRequest: Encodable {
    let disposition: OpportunityDisposition
    let changedAt: Date
    let mutationID: UUID

    init(_ mutation: OpportunityDispositionMutation) {
        disposition = mutation.disposition
        changedAt = mutation.changedAt
        mutationID = mutation.id
    }
}

private struct RemoteDisposition: Decodable {
    let id: UUID
    let disposition: OpportunityDisposition
    let dispositionUpdatedAt: Date
    let dispositionMutationID: UUID?

    var state: OpportunityDispositionState {
        OpportunityDispositionState(
            opportunityID: id,
            disposition: disposition,
            changedAt: dispositionUpdatedAt,
            mutationID: dispositionMutationID ?? UUID(),
            outcome: nil
        )
    }
}

private enum BackendSyncError: Error {
    case httpStatus(Int)
    case invalidResponse
}

struct NoopResearchSync: ResearchSyncing {
    func synchronize() async -> [SourceSyncResult] {
        SourceGroup.allCases.map {
            SourceSyncResult(
                group: $0,
                collectedAt: .now,
                items: [],
                state: .setupRequired,
                dataTruth: .missing,
                evidence: "No live connector is configured."
            )
        }
    }
}

struct LocalResearchSync: ResearchSyncing {
    private let officialConnectors: [any ProductionSourceConnector]
    private let environment: [String: String]
    private let credentialStore: any CredentialStoring

    init(
        officialConnectors: [any ProductionSourceConnector] = OfficialAISourceCatalog.starter.map {
            PublicFeedConnector(source: $0)
        },
        environment: [String: String] = ProcessInfo.processInfo.environment,
        credentialStore: any CredentialStoring = InMemoryCredentialStore()
    ) {
        self.officialConnectors = officialConnectors
        self.environment = environment
        self.credentialStore = credentialStore
    }

    func synchronize() async -> [SourceSyncResult] {
        await synchronize(watchlist: [])
    }

    func synchronize(watchlist: [WatchlistEntry]) async -> [SourceSyncResult] {
        let planned = officialConnectors.map {
            GroupedSourceConnector(group: .official, connector: $0)
        } + WatchlistConnectorFactory.connectors(
            for: watchlist,
            environment: environment,
            credentialStore: credentialStore
        )
        let collections = await withTaskGroup(of: LocalGroupedCollection.self) { group in
            for connector in planned {
                group.addTask {
                    LocalGroupedCollection(
                        group: connector.group,
                        collection: await connector.connector.collect()
                    )
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        return SourceGroup.allCases.map { sourceGroup in
            result(
                for: sourceGroup,
                collections: collections.filter { $0.group == sourceGroup }.map(\.collection)
            )
        }
    }

    private func result(for group: SourceGroup, collections: [ConnectorCollection]) -> SourceSyncResult {
        guard !collections.isEmpty else {
            return unavailableResult(for: group)
        }
        let collectedAt = collections.map(\.collectedAt).max() ?? .now
        let usable = collections.filter {
            $0.state == .available || $0.state == .notModified || $0.state == .delayed
        }
        let items = usable.flatMap(\.items)
        let evidence = collections.map(\.evidence).filter { !$0.isEmpty }.joined(separator: " ")
        if !usable.isEmpty {
            let hasCurrentSource = usable.contains { $0.state == .available }
            let isDelayed = !hasCurrentSource
            return SourceSyncResult(
                group: group,
                collectedAt: collectedAt,
                items: items,
                state: isDelayed ? .delayed : .connected,
                dataTruth: isDelayed ? .delayed : .live,
                evidence: evidence
            )
        }
        if collections.contains(where: {
            if case .rateLimited = $0.state { return true }
            return false
        }) {
            return SourceSyncResult(
                group: group,
                collectedAt: collectedAt,
                items: [],
                state: .rateLimited,
                dataTruth: .rateLimited,
                evidence: evidence
            )
        }
        if group == .googleTrends {
            return SourceSyncResult(
                group: group,
                collectedAt: collectedAt,
                items: [],
                state: .unsupported,
                dataTruth: .unavailable,
                evidence: evidence
            )
        }
        let setupRequired = evidence.localizedCaseInsensitiveContains("credential")
            || evidence.localizedCaseInsensitiveContains("setup required")
            || evidence.localizedCaseInsensitiveContains("not configured")
        return SourceSyncResult(
            group: group,
            collectedAt: collectedAt,
            items: [],
            state: setupRequired ? .setupRequired : .unavailable,
            dataTruth: setupRequired ? .missing : .unavailable,
            evidence: evidence
        )
    }

    private func unavailableResult(for group: SourceGroup) -> SourceSyncResult {
        let state: ConnectionState = group == .googleTrends ? .unsupported : .setupRequired
        let evidence: String
        switch group {
        case .youtube:
            evidence = "A YouTube Data API key and at least one creator or topic watchlist are required."
        case .comments:
            evidence = "Comments use the same YouTube Data API key and watched videos."
        case .googleTrends:
            evidence = "Official Google Trends API access is approval-gated and is not enabled in this local build."
        case .instagram:
            evidence = "A long-lived professional-account token and at least one creator watchlist are required."
        case .x:
            evidence = "An X API read bearer token and at least one creator or topic watchlist are required."
        case .official:
            evidence = "No credential-free official source connector is configured."
        }
        return SourceSyncResult(
            group: group,
            collectedAt: .now,
            items: [],
            state: state,
            dataTruth: group == .googleTrends ? .unavailable : .missing,
            evidence: evidence
        )
    }
}

private struct LocalGroupedCollection: Sendable {
    let group: SourceGroup
    let collection: ConnectorCollection
}

struct ProductionResearchSync: ResearchSyncing {
    private let backend: BackendResearchSync?
    private let local: LocalResearchSync
    private let environment: [String: String]

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
        self.local = LocalResearchSync(environment: environment)
        guard
            let rawURL = environment["ZOID99_API_BASE_URL"],
            let baseURL = URL(string: rawURL),
            let token = environment["ZOID99_API_TOKEN"],
            token.count >= 32
        else {
            backend = nil
            return
        }
        backend = BackendResearchSync(baseURL: baseURL, token: token)
    }

    func synchronize() async -> [SourceSyncResult] {
        guard let backend else { return await local.synchronize() }
        return await backend.synchronize()
    }

    func synchronize(watchlist: [WatchlistEntry]) async -> [SourceSyncResult] {
        guard let backend else { return await local.synchronize(watchlist: watchlist) }
        return await backend.synchronize(
            additionalConnectors: WatchlistConnectorFactory.connectors(
                for: watchlist,
                environment: environment
            )
        )
    }

    func synchronize(watchlist: [WatchlistEntry], seed: ResearchSyncSeed) async -> [SourceSyncResult] {
        guard let backend else { return await local.synchronize(watchlist: watchlist) }
        return await backend.synchronize(
            additionalConnectors: WatchlistConnectorFactory.connectors(
                for: watchlist,
                environment: environment
            ),
            seed: seed
        )
    }
}
