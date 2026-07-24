import Foundation
import Security

struct SourceSyncResult: Sendable {
    let group: SourceGroup
    let collectedAt: Date
    let items: [SourceItem]
    let state: ConnectionState
    let dataTruth: DataTruth
    let evidence: String
}
protocol ResearchSyncing: Sendable {
    func synchronize() async -> [SourceSyncResult]
    func synchronize(watchlist: [WatchlistEntry]) async -> [SourceSyncResult]
    func researchTopic(_ query: String, watchlist: [WatchlistEntry]) async -> [SourceSyncResult]
}

extension ResearchSyncing {
    func synchronize(watchlist: [WatchlistEntry]) async -> [SourceSyncResult] {
        await synchronize()
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
              let apiToken = environment["ZOID99_API_TOKEN"] ?? ProductionResearchSync.keychainToken(),
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
        guard let rawURL = environment["ZOID99_BACKEND_URL"],
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
            let response = try await transport.send(
                HTTPRequest(
                    url: baseURL.appendingPathComponent("v1/opportunities"),
                    headers: authorizedHeaders
                )
            )
            guard response.statusCode == 200 else {
                throw BackendSyncError.httpStatus(response.statusCode)
            }
            states.append(contentsOf: try Self.decoder.decode([RemoteDisposition].self, from: response.body).map(\.state))
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
        credentialStore: any CredentialStoring = KeychainCredentialStore()
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
            let token = environment["ZOID99_API_TOKEN"] ?? Self.keychainToken(),
            token.count >= 32
        else {
            backend = nil
            return
        }
        backend = BackendResearchSync(baseURL: baseURL, token: token)
    }

    static func keychainToken() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "Zoid99Backend",
            kSecAttrAccount: "api-token",
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
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
}
