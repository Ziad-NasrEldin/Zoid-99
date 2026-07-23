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

struct ProductionResearchSync: ResearchSyncing {
    private let backend: BackendResearchSync?

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
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

    private static func keychainToken() -> String? {
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
        guard let backend else { return await NoopResearchSync().synchronize() }
        return await backend.synchronize()
    }
}
