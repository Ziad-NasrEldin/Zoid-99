import Foundation

actor BackendResearchSync {
    private let baseURL: URL
    private let token: String
    private let session: URLSession
    private let connectors: [any ProductionSourceConnector]
    private var bootstrapETag: String?

    init(
        baseURL: URL,
        token: String,
        session: URLSession = .shared,
        connectors: [any ProductionSourceConnector] = OfficialAISourceCatalog.starter.map {
            PublicFeedConnector(source: $0)
        }
    ) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
        self.connectors = connectors
    }

    func synchronize() async -> [SourceSyncResult] {
        let collections = await withTaskGroup(of: ConnectorCollection.self) { group in
            for connector in connectors {
                group.addTask { await connector.collect() }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        let changedItems = collections
            .filter { $0.state == .available || $0.state == .delayed }
            .flatMap(\.items)
        let officialHealth = makeOfficialHealth(collections)

        do {
            if !changedItems.isEmpty {
                let output = ResearchPipeline().run(items: changedItems)
                try await ingest(output: output, sourceHealth: allSourceHealth(official: officialHealth))
            }
            guard let bootstrap = try await bootstrap() else {
                return unchangedResults(official: officialHealth)
            }
            return results(from: bootstrap)
        } catch {
            return SourceGroup.allCases.map { group in
                SourceSyncResult(
                    group: group,
                    collectedAt: .now,
                    items: [],
                    state: group == .official ? .unavailable : .setupRequired,
                    dataTruth: group == .official ? .unavailable : .missing,
                    evidence: group == .official
                        ? "Backend synchronization failed after bounded retries: \(error.localizedDescription)"
                        : "This source is not configured."
                )
            }
        }
    }

    private func ingest(output: ResearchOutput, sourceHealth: [APIHealth]) async throws {
        let notifications = Dictionary(uniqueKeysWithValues: output.notifications.map { ($0.opportunityID, $0) })
        let batches = output.opportunities.map { opportunity in
                IngestionBatch(
                    clusterKey: opportunity.topicKey,
                    topicKey: opportunity.topicKey,
                    verification: opportunity.verification,
                    originState: opportunity.originalSource == nil ? "Unknown" : "Identified",
                    originalSource: opportunity.originalSource.map {
                        OriginalSource(group: $0.group, externalID: $0.externalID)
                    },
                    sourceItems: opportunity.items.map(APIItem.init),
                    opportunity: APIOpportunityInput(opportunity),
                    notification: notifications[opportunity.id].map(APINotificationInput.init)
                )
            }
        for start in stride(from: 0, to: batches.count, by: 5) {
            let end = min(start + 5, batches.count)
            let payload = IngestionRequest(
                sourceHealth: sourceHealth,
                batches: Array(batches[start..<end])
            )
            var request = authorizedRequest(path: "v1/ingestion", method: "POST")
            request.httpBody = try apiEncoder.encode(payload)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (data, response) = try await sendWithRetry(request)
            guard response.statusCode == 202 else {
                throw SyncError.http(response.statusCode, String(data: data, encoding: .utf8) ?? "")
            }
        }
    }

    private func bootstrap() async throws -> BootstrapResponse? {
        var request = authorizedRequest(path: "v1/bootstrap", method: "GET")
        if let bootstrapETag {
            request.setValue(bootstrapETag, forHTTPHeaderField: "If-None-Match")
        }
        let (data, response) = try await sendWithRetry(request)
        if response.statusCode == 304 { return nil }
        guard response.statusCode == 200 else {
            throw SyncError.http(response.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        bootstrapETag = response.value(forHTTPHeaderField: "ETag")
        return try apiDecoder.decode(BootstrapResponse.self, from: data)
    }

    private func sendWithRetry(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var finalError: Error = SyncError.invalidResponse
        for attempt in 1...3 {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw SyncError.invalidResponse }
                if http.statusCode < 500 && http.statusCode != 429 { return (data, http) }
                finalError = SyncError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
            } catch {
                finalError = error
            }
            if attempt < 3 {
                try? await Task.sleep(for: .milliseconds(200 * attempt))
            }
        }
        throw finalError
    }

    private func authorizedRequest(path: String, method: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func makeOfficialHealth(_ collections: [ConnectorCollection]) -> APIHealth {
        let latest = collections.map(\.collectedAt).max()
        let liveCount = collections.filter { $0.state == .available || $0.state == .delayed }.flatMap(\.items).count
        if collections.contains(where: {
            if case .rateLimited = $0.state { return true }
            return false
        }) {
            return APIHealth(group: .official, state: .rateLimited, lastActivity: latest,
                             evidence: collections.map(\.evidence).joined(separator: " "), repairAction: "Retry later",
                             dataTruth: .rateLimited)
        }
        if liveCount > 0 {
            return APIHealth(group: .official, state: .connected, lastActivity: latest,
                             evidence: "\(liveCount) official-feed items collected with source links and timestamps.",
                             repairAction: "Review", dataTruth: .live)
        }
        if collections.allSatisfy({ $0.state == .notModified }) {
            return APIHealth(group: .official, state: .connected, lastActivity: latest,
                             evidence: "Official feeds are unchanged since the last successful collection.",
                             repairAction: "Review", dataTruth: .cached)
        }
        return APIHealth(group: .official, state: .unavailable, lastActivity: latest,
                         evidence: collections.map(\.evidence).joined(separator: " "), repairAction: "Retry",
                         dataTruth: .unavailable)
    }

    private func allSourceHealth(official: APIHealth) -> [APIHealth] {
        SourceGroup.allCases.map { group in
            group == .official ? official : APIHealth(
                group: group, state: .setupRequired, lastActivity: nil,
                evidence: "This source is not configured.", repairAction: "Configure", dataTruth: .missing
            )
        }
    }

    private func results(from bootstrap: BootstrapResponse) -> [SourceSyncResult] {
        let items = bootstrap.opportunities.flatMap(\.items)
        return bootstrap.sourceHealth.map { health in
            SourceSyncResult(
                group: health.group,
                collectedAt: health.lastActivity ?? .now,
                items: items.filter { $0.group == health.group }.map(\.model),
                state: health.state,
                dataTruth: health.dataTruth,
                evidence: health.evidence
            )
        }
    }

    private func unchangedResults(official: APIHealth) -> [SourceSyncResult] {
        allSourceHealth(official: official).map {
            SourceSyncResult(
                group: $0.group, collectedAt: $0.lastActivity ?? .now, items: [],
                state: $0.state, dataTruth: $0.dataTruth, evidence: $0.evidence
            )
        }
    }
}

private enum SyncError: LocalizedError {
    case http(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .http(let status, let detail):
            "Backend returned HTTP \(status)\(detail.isEmpty ? "." : ": \(String(detail.prefix(1_000)))")"
        case .invalidResponse: "Backend response was invalid."
        }
    }
}

private struct IngestionRequest: Encodable {
    let sourceHealth: [APIHealth]
    let batches: [IngestionBatch]
}

private struct IngestionBatch: Encodable {
    let clusterKey: String
    let topicKey: String
    let verification: VerificationState
    let originState: String
    let originalSource: OriginalSource?
    let sourceItems: [APIItem]
    let opportunity: APIOpportunityInput
    let notification: APINotificationInput?
}

private struct OriginalSource: Codable {
    let group: SourceGroup
    let externalID: String
}

private struct APIHealth: Codable {
    let group: SourceGroup
    let state: ConnectionState
    let lastActivity: Date?
    let evidence: String
    let repairAction: String
    let dataTruth: DataTruth
}

private struct APIItem: Codable {
    let id: UUID?
    let group: SourceGroup
    let externalID: String
    let title: String
    let summary: String
    let author: String
    let url: URL
    let publishedAt: Date
    let collectedAt: Date
    let language: String
    let country: String
    let topicKey: String
    let isOriginalSource: Bool
    let credibility: Double
    let engagement: Int
    let verification: VerificationState

    init(_ item: SourceItem) {
        id = nil
        group = item.group
        externalID = item.externalID
        title = item.title
        summary = item.summary
        author = item.author
        url = item.url
        publishedAt = item.publishedAt
        collectedAt = item.collectedAt
        language = item.language
        country = item.country
        topicKey = item.topicKey
        isOriginalSource = item.isOriginalSource
        credibility = item.credibility
        engagement = item.engagement
        verification = item.verification
    }

    var model: SourceItem {
        SourceItem(
            id: id ?? UUID(), group: group, externalID: externalID, title: title, summary: summary,
            author: author, url: url, publishedAt: publishedAt, collectedAt: collectedAt,
            language: language, country: country, topicKey: topicKey, isOriginalSource: isOriginalSource,
            credibility: credibility, engagement: engagement, verification: verification, dataTruth: .live
        )
    }
}

private struct APIOpportunityInput: Encodable {
    let title: String
    let brief: String
    let score: ScoreBreakdown
    let regionalExplanation: String
    let coverageExplanation: String
    let disposition: OpportunityDisposition

    init(_ opportunity: Opportunity) {
        title = opportunity.title
        brief = opportunity.brief
        score = opportunity.score
        regionalExplanation = opportunity.regionalExplanation
        coverageExplanation = opportunity.coverageExplanation
        disposition = opportunity.disposition
    }
}

private struct APINotificationInput: Encodable {
    let title: String
    let delivery: NotificationRecord.Delivery
    let createdAt: Date
    let isRead: Bool

    init(_ notification: NotificationRecord) {
        title = notification.title
        delivery = notification.delivery
        createdAt = notification.createdAt
        isRead = notification.isRead
    }
}

private struct BootstrapResponse: Decodable {
    let sourceHealth: [APIHealth]
    let opportunities: [APIOpportunity]
}

private struct APIOpportunity: Decodable {
    let items: [APIItem]
}

private let apiEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}()

private let apiDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}()
