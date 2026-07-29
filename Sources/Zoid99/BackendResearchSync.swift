import Foundation

actor BackendResearchSync {
    private static let maximumIngestionBodyBytes = 60 * 1024

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

    func synchronize(
        additionalConnectors: [GroupedSourceConnector] = [],
        seed: ResearchSyncSeed? = nil
    ) async -> [SourceSyncResult] {
        let plannedConnectors = connectors.map {
            GroupedSourceConnector(group: .official, connector: $0)
        } + additionalConnectors
        let collections = await withTaskGroup(of: GroupedConnectorCollection.self) { group in
            for planned in plannedConnectors {
                group.addTask {
                    GroupedConnectorCollection(
                        group: planned.group,
                        collection: await planned.connector.collect()
                    )
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        let usableCollections = collections
            .map(\.collection)
            .filter { $0.state == .available || $0.state == .delayed }
        let collectedItems = usableCollections.flatMap(\.items)
        let blockedRules = seed?.sourceBlocklist ?? []
        let changedItems = collectedItems.filter { !isBlocked($0, by: blockedRules) }
        let sourceHealth = makeSourceHealth(collections)

        do {
            if !changedItems.isEmpty {
                let output = ResearchPipeline().run(items: changedItems)
                try await ingest(output: output, sourceHealth: sourceHealth)
            }
            guard var canonicalBootstrap = try await bootstrap() else {
                return unchangedResults(sourceHealth)
            }
            if let seed, !seed.sourceItems.isEmpty {
                let remoteItemKeys = Set(
                    canonicalBootstrap.opportunities
                        .flatMap(\.items)
                        .map { "\($0.group.rawValue):\($0.externalID)" }
                )
                let missingTopicKeys = Set(
                    seed.sourceItems
                        .filter { !remoteItemKeys.contains("\($0.group.rawValue):\($0.externalID)") }
                        .map(\.topicKey)
                )
                let itemsToImport = seed.sourceItems.filter { missingTopicKeys.contains($0.topicKey) }
                let remoteOpportunitiesByTopic = Dictionary(
                    uniqueKeysWithValues: canonicalBootstrap.opportunities.map { ($0.topicKey, $0) }
                )
                var remoteOpportunitiesBySourceURL: [URL: APIOpportunity] = [:]
                for remoteOpportunity in canonicalBootstrap.opportunities {
                    for item in remoteOpportunity.items where remoteOpportunitiesBySourceURL[item.url] == nil {
                        remoteOpportunitiesBySourceURL[item.url] = remoteOpportunity
                    }
                }
                let remoteNotificationOpportunityIDs = Set(
                    canonicalBootstrap.notifications.map(\.opportunityID)
                )
                let seedNotificationsByOpportunityID = Dictionary(
                    uniqueKeysWithValues: seed.notifications.map { ($0.opportunityID, $0) }
                )
                let seedOpportunitiesToSync = seed.opportunities.compactMap { opportunity -> Opportunity? in
                    let matchingRemote = remoteOpportunitiesByTopic[opportunity.topicKey]
                        ?? opportunity.items.compactMap { remoteOpportunitiesBySourceURL[$0.url] }.first
                    if let matchingRemote {
                        guard seedNotificationsByOpportunityID[opportunity.id] != nil,
                              !remoteNotificationOpportunityIDs.contains(matchingRemote.id) else {
                            return nil
                        }
                        return Opportunity(
                            id: opportunity.id,
                            topicKey: matchingRemote.topicKey,
                            title: opportunity.title,
                            brief: opportunity.brief,
                            verification: opportunity.verification,
                            earliestPublishedAt: opportunity.earliestPublishedAt,
                            originalSource: opportunity.originalSource,
                            items: opportunity.items,
                            score: opportunity.score,
                            regionalExplanation: opportunity.regionalExplanation,
                            coverageExplanation: opportunity.coverageExplanation,
                            disposition: opportunity.disposition,
                            dispositionUpdatedAt: opportunity.dispositionUpdatedAt,
                            dispositionMutationID: opportunity.dispositionMutationID
                        )
                    }
                    return missingTopicKeys.contains(opportunity.topicKey) ? opportunity : nil
                }
                guard !itemsToImport.isEmpty || !seedOpportunitiesToSync.isEmpty else {
                    return results(from: canonicalBootstrap)
                }
                let generatedOutput = ResearchPipeline().run(items: itemsToImport)
                let opportunitiesToSync = seedOpportunitiesToSync.isEmpty
                    ? generatedOutput.opportunities
                    : seedOpportunitiesToSync
                let importedOpportunityIDs = Set(opportunitiesToSync.map(\.id))
                let storedNotifications = seed.notifications.filter {
                    importedOpportunityIDs.contains($0.opportunityID)
                }
                let seedOutput = ResearchOutput(
                    normalizedItems: itemsToImport,
                    opportunities: opportunitiesToSync,
                    comments: generatedOutput.comments,
                    notifications: storedNotifications.isEmpty
                        ? generatedOutput.notifications
                        : storedNotifications,
                    aiStatus: generatedOutput.aiStatus,
                    aiInterpretations: generatedOutput.aiInterpretations
                )
                try await ingest(
                    output: seedOutput,
                    sourceHealth: seed.sourceHealth.isEmpty
                        ? sourceHealth
                        : seed.sourceHealth.map(APIHealth.init)
                )
                bootstrapETag = nil
                if let seededBootstrap = try await bootstrap() {
                    canonicalBootstrap = seededBootstrap
                }
            }
            return results(from: canonicalBootstrap)
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
        let batches = try output.opportunities.flatMap { opportunity in
            try ingestionBatches(
                for: opportunity,
                notification: notifications[opportunity.id],
                sourceHealth: sourceHealth
            )
        }
        var requestBatches: [IngestionBatch] = []
        for batch in batches {
            let candidate = requestBatches + [batch]
            if try encodedBodySize(sourceHealth: sourceHealth, batches: candidate) <= Self.maximumIngestionBodyBytes {
                requestBatches = candidate
            } else {
                try await sendIngestion(sourceHealth: sourceHealth, batches: requestBatches)
                requestBatches = [batch]
            }
        }
        try await sendIngestion(sourceHealth: sourceHealth, batches: requestBatches)
    }

    private func ingestionBatches(
        for opportunity: Opportunity,
        notification: NotificationRecord?,
        sourceHealth: [APIHealth]
    ) throws -> [IngestionBatch] {
        let original = opportunity.originalSource
        let remaining = opportunity.items.filter {
            guard let original else { return true }
            return $0.group != original.group || $0.externalID != original.externalID
        }
        var chunks: [[SourceItem]] = []
        var current = original.map { [$0] } ?? []

        for item in remaining {
            let candidate = current + [item]
            let batch = makeIngestionBatch(
                opportunity: opportunity,
                sourceItems: candidate,
                notification: notification
            )
            if try encodedBodySize(sourceHealth: sourceHealth, batches: [batch]) <= Self.maximumIngestionBodyBytes {
                current = candidate
            } else {
                guard !current.isEmpty else { throw SyncError.payloadTooLarge }
                chunks.append(current)
                current = original.map { [$0, item] } ?? [item]
                let next = makeIngestionBatch(
                    opportunity: opportunity,
                    sourceItems: current,
                    notification: notification
                )
                guard try encodedBodySize(sourceHealth: sourceHealth, batches: [next])
                        <= Self.maximumIngestionBodyBytes else {
                    throw SyncError.payloadTooLarge
                }
            }
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks.map {
            makeIngestionBatch(opportunity: opportunity, sourceItems: $0, notification: notification)
        }
    }

    private func makeIngestionBatch(
        opportunity: Opportunity,
        sourceItems: [SourceItem],
        notification: NotificationRecord?
    ) -> IngestionBatch {
        IngestionBatch(
            clusterKey: opportunity.topicKey,
            topicKey: opportunity.topicKey,
            verification: opportunity.verification,
            originState: opportunity.originalSource == nil ? "Unknown" : "Identified",
            originalSource: opportunity.originalSource.map {
                OriginalSource(group: $0.group, externalID: $0.externalID)
            },
            sourceItems: sourceItems.map(APIItem.init),
            opportunity: APIOpportunityInput(opportunity),
            notification: notification.map(APINotificationInput.init)
        )
    }

    private func encodedBodySize(sourceHealth: [APIHealth], batches: [IngestionBatch]) throws -> Int {
        try apiEncoder.encode(IngestionRequest(sourceHealth: sourceHealth, batches: batches)).count
    }

    private func sendIngestion(sourceHealth: [APIHealth], batches: [IngestionBatch]) async throws {
        guard !batches.isEmpty else { return }
        let payload = IngestionRequest(sourceHealth: sourceHealth, batches: batches)
        let body = try apiEncoder.encode(payload)
        guard body.count <= Self.maximumIngestionBodyBytes else { throw SyncError.payloadTooLarge }
        var request = authorizedRequest(path: "v1/ingestion", method: "POST")
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await sendWithRetry(request)
        guard response.statusCode == 202 else {
            throw SyncError.http(response.statusCode, String(data: data, encoding: .utf8) ?? "")
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

    private func isBlocked(_ item: SourceItem, by rules: [SourceBlockRule]) -> Bool {
        guard let domain = SourceDomainNormalizer.normalizedDomain(from: item.url) else {
            return false
        }
        return rules.contains { rule in
            let subdomainSuffix = "." + rule.domain
            return domain == rule.domain || domain.hasSuffix(subdomainSuffix)
        }
    }

    private func makeSourceHealth(_ grouped: [GroupedConnectorCollection]) -> [APIHealth] {
        SourceGroup.allCases.map { group in
            makeHealth(
                group: group,
                collections: grouped.filter { $0.group == group }.map(\.collection)
            )
        }
    }

    private func makeHealth(group: SourceGroup, collections: [ConnectorCollection]) -> APIHealth {
        guard !collections.isEmpty else {
            return APIHealth(
                group: group,
                state: .setupRequired,
                lastActivity: nil,
                evidence: "This source is not configured.",
                repairAction: "Configure",
                dataTruth: .missing
            )
        }
        let latest = collections.map(\.collectedAt).max()
        let evidence = collections.map(\.evidence).joined(separator: " ")
        if collections.contains(where: {
            if case .rateLimited = $0.state { return true }
            return false
        }) {
            return APIHealth(group: group, state: .rateLimited, lastActivity: latest,
                             evidence: evidence, repairAction: "Retry later",
                             dataTruth: .rateLimited)
        }
        if collections.contains(where: { $0.state == .available }) {
            let liveCount = collections.filter { $0.state == .available }.flatMap(\.items).count
            return APIHealth(group: group, state: .connected, lastActivity: latest,
                             evidence: liveCount == 0 ? evidence : "\(liveCount) \(group.rawValue) items collected with source links and timestamps.",
                             repairAction: "Review", dataTruth: .live)
        }
        if collections.contains(where: { $0.state == .delayed }) {
            return APIHealth(group: group, state: .delayed, lastActivity: latest,
                             evidence: evidence, repairAction: "Refresh", dataTruth: .delayed)
        }
        if collections.allSatisfy({ $0.state == .notModified }) {
            return APIHealth(group: group, state: .connected, lastActivity: latest,
                             evidence: "\(group.rawValue) is unchanged since the last successful collection.",
                             repairAction: "Review", dataTruth: .cached)
        }
        let setupRequired = evidence.localizedCaseInsensitiveContains("setup required")
            || evidence.localizedCaseInsensitiveContains("credential")
            || evidence.localizedCaseInsensitiveContains("not configured")
        return APIHealth(group: group, state: setupRequired ? .setupRequired : .unavailable, lastActivity: latest,
                         evidence: evidence, repairAction: setupRequired ? "Configure" : "Retry",
                         dataTruth: setupRequired ? .missing : .unavailable)
    }

    private func results(from bootstrap: BootstrapResponse) -> [SourceSyncResult] {
        let truthByGroup = Dictionary(
            uniqueKeysWithValues: bootstrap.sourceHealth.map { ($0.group, $0.dataTruth) }
        )
        let opportunities = bootstrap.opportunities.map { $0.model(dataTruthByGroup: truthByGroup) }
        let items = opportunities.flatMap(\.items)
        let notifications = bootstrap.notifications.map(\.model)
        return bootstrap.sourceHealth.map { health in
            SourceSyncResult(
                group: health.group,
                collectedAt: health.lastActivity ?? .now,
                items: items.filter { $0.group == health.group },
                state: health.state,
                dataTruth: health.dataTruth,
                evidence: health.evidence,
                canonicalOpportunities: opportunities,
                canonicalNotifications: notifications
            )
        }
    }

    private func unchangedResults(_ sourceHealth: [APIHealth]) -> [SourceSyncResult] {
        sourceHealth.map {
            SourceSyncResult(
                group: $0.group, collectedAt: $0.lastActivity ?? .now, items: [],
                state: $0.state, dataTruth: $0.dataTruth, evidence: $0.evidence
            )
        }
    }
}

private struct GroupedConnectorCollection: Sendable {
    let group: SourceGroup
    let collection: ConnectorCollection
}

private enum SyncError: LocalizedError {
    case http(Int, String)
    case invalidResponse
    case payloadTooLarge

    var errorDescription: String? {
        switch self {
        case .http(let status, let detail):
            "Backend returned HTTP \(status)\(detail.isEmpty ? "." : ": \(String(detail.prefix(1_000)))")"
        case .invalidResponse: "Backend response was invalid."
        case .payloadTooLarge: "One normalized source item exceeds the safe backend ingestion limit."
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

    init(
        group: SourceGroup,
        state: ConnectionState,
        lastActivity: Date?,
        evidence: String,
        repairAction: String,
        dataTruth: DataTruth
    ) {
        self.group = group
        self.state = state
        self.lastActivity = lastActivity
        self.evidence = evidence
        self.repairAction = repairAction
        self.dataTruth = dataTruth
    }

    init(_ health: SourceHealth) {
        group = health.group
        state = health.state
        lastActivity = health.lastActivity
        evidence = health.evidence
        repairAction = health.repairAction
        dataTruth = health.dataTruth
    }
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
        model(dataTruth: .live)
    }

    func model(dataTruth: DataTruth) -> SourceItem {
        SourceItem(
            id: id ?? UUID(), group: group, externalID: externalID, title: title, summary: summary,
            author: author, url: url, publishedAt: publishedAt, collectedAt: collectedAt,
            language: language, country: country, topicKey: topicKey, isOriginalSource: isOriginalSource,
            credibility: credibility, engagement: engagement, verification: verification, dataTruth: dataTruth
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
    let notifications: [APINotification]
}

private struct APIOpportunity: Decodable {
    let id: UUID
    let topicKey: String
    let title: String
    let brief: String
    let verification: VerificationState
    let earliestPublishedAt: Date
    let originalSource: APIItem?
    let items: [APIItem]
    let score: ScoreBreakdown
    let regionalExplanation: String
    let coverageExplanation: String
    let disposition: OpportunityDisposition
    let dispositionUpdatedAt: Date?
    let dispositionMutationID: UUID?

    func model(dataTruthByGroup: [SourceGroup: DataTruth]) -> Opportunity {
        Opportunity(
            id: id,
            topicKey: topicKey,
            title: title,
            brief: brief,
            verification: verification,
            earliestPublishedAt: earliestPublishedAt,
            originalSource: originalSource.map {
                $0.model(dataTruth: dataTruthByGroup[$0.group] ?? .cached)
            },
            items: items.map { $0.model(dataTruth: dataTruthByGroup[$0.group] ?? .cached) },
            score: score,
            regionalExplanation: regionalExplanation,
            coverageExplanation: coverageExplanation,
            disposition: disposition,
            dispositionUpdatedAt: dispositionUpdatedAt,
            dispositionMutationID: dispositionMutationID
        )
    }
}

private struct APINotification: Decodable {
    let id: UUID
    let opportunityID: UUID
    let title: String
    let delivery: NotificationRecord.Delivery
    let createdAt: Date
    let isRead: Bool

    var model: NotificationRecord {
        NotificationRecord(
            id: id,
            opportunityID: opportunityID,
            title: title,
            delivery: delivery,
            createdAt: createdAt,
            isRead: isRead
        )
    }
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
