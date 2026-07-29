import Foundation
import XCTest
@testable import Zoid99

final class IngestionSynchronizationAcceptanceTests: XCTestCase {
    func testOfficialFeedTravelsThroughAuthenticatedIngestionAndBackThroughBootstrap() async throws {
        let item = SourceItem(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000099")!,
            group: .official,
            externalID: "official-entry-99",
            title: "Official release 99",
            summary: "Primary-source release evidence.",
            author: "Official publisher",
            url: URL(string: "https://official.example/releases/99")!,
            publishedAt: Date(timeIntervalSince1970: 1_784_908_800),
            collectedAt: Date(timeIntervalSince1970: 1_784_909_100),
            language: "en",
            country: "US",
            topicKey: "official-entry-99",
            isOriginalSource: true,
            credibility: 1,
            engagement: 0,
            verification: .confirmed,
            dataTruth: .live
        )
        let connector = AcceptanceConnector(item: item)
        let recorder = RequestRecorder(item: item)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AcceptanceURLProtocol.self]
        AcceptanceURLProtocol.recorder = recorder
        let sync = BackendResearchSync(
            baseURL: URL(string: "https://backend.example")!,
            token: "acceptance-test-token-with-32-characters",
            session: URLSession(configuration: configuration),
            connectors: [connector]
        )

        let results = await sync.synchronize()

        let official = try XCTUnwrap(results.first { $0.group == .official })
        XCTAssertEqual(official.state, .connected)
        XCTAssertEqual(official.dataTruth, .live)
        XCTAssertEqual(official.items.first?.externalID, item.externalID)
        XCTAssertEqual(official.items.first?.url, item.url)
        XCTAssertEqual(
            official.canonicalOpportunities?.first?.id,
            UUID(uuidString: "20000000-0000-4000-8000-000000000099")
        )
        let paths = await recorder.paths()
        XCTAssertEqual(paths, ["/v1/ingestion", "/v1/bootstrap"])
        let ingestion = try await recorder.ingestionJSON()
        let sourceHealth = try XCTUnwrap(ingestion["sourceHealth"] as? [[String: Any]])
        XCTAssertEqual(
            sourceHealth.first { $0["group"] as? String == SourceGroup.official.rawValue }?["dataTruth"] as? String,
            "Live"
        )
        let batches = try XCTUnwrap(ingestion["batches"] as? [[String: Any]])
        let items = try XCTUnwrap(batches.first?["sourceItems"] as? [[String: Any]])
        XCTAssertEqual(items.first?["url"] as? String, item.url.absoluteString)
        XCTAssertEqual(items.first?["publishedAt"] as? String, ISO8601DateFormatter().string(from: item.publishedAt))
    }

    func testEmptyBackendImportsTheNativeCacheThenReturnsCanonicalServerIDs() async throws {
        let item = SourceItem(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000088")!,
            group: .official,
            externalID: "native-cache-88",
            title: "Native cache release",
            summary: "Existing native research should become available to the web client.",
            author: "Official publisher",
            url: URL(string: "https://official.example/releases/88")!,
            publishedAt: Date(timeIntervalSince1970: 1_784_808_800),
            collectedAt: Date(timeIntervalSince1970: 1_784_809_100),
            language: "en",
            country: "US",
            topicKey: "native-cache-88",
            isOriginalSource: true,
            credibility: 1,
            engagement: 0,
            verification: .confirmed,
            dataTruth: .cached
        )
        let recorder = RequestRecorder(item: item, startsEmpty: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AcceptanceURLProtocol.self]
        AcceptanceURLProtocol.recorder = recorder
        let sync = BackendResearchSync(
            baseURL: URL(string: "https://backend.example")!,
            token: String(repeating: "t", count: 32),
            session: URLSession(configuration: configuration),
            connectors: []
        )
        let health = SourceHealth(
            group: .official,
            state: .connected,
            lastActivity: item.collectedAt,
            evidence: "Native cache contains verified research.",
            repairAction: "Review",
            dataTruth: .cached
        )

        let results = await sync.synchronize(
            seed: ResearchSyncSeed(
                sourceItems: [item],
                sourceHealth: [health],
                notifications: [],
                sourceBlocklist: []
            )
        )

        XCTAssertEqual(
            results.first?.canonicalOpportunities?.first?.id,
            UUID(uuidString: "20000000-0000-4000-8000-000000000099")
        )
        XCTAssertEqual(results.first?.canonicalOpportunities?.first?.items.first?.externalID, item.externalID)
        let paths = await recorder.paths()
        XCTAssertEqual(paths, ["/v1/bootstrap", "/v1/ingestion", "/v1/bootstrap"])
    }

    func testBlockedConnectorItemsNeverEnterTheSharedBackend() async throws {
        let item = SourceItem(
            id: UUID(),
            group: .official,
            externalID: "blocked-arxiv-item",
            title: "Blocked source item",
            summary: "This record must stay out of the shared dataset.",
            author: "Blocked publisher",
            url: URL(string: "https://arxiv.org/abs/2607.00001")!,
            publishedAt: Date(timeIntervalSince1970: 1_784_808_800),
            collectedAt: Date(timeIntervalSince1970: 1_784_809_100),
            language: "en",
            country: "US",
            topicKey: "blocked-arxiv-item",
            isOriginalSource: true,
            credibility: 1,
            engagement: 0,
            verification: .confirmed,
            dataTruth: .live
        )
        let recorder = RequestRecorder(item: item)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AcceptanceURLProtocol.self]
        AcceptanceURLProtocol.recorder = recorder
        let sync = BackendResearchSync(
            baseURL: URL(string: "https://backend.example")!,
            token: String(repeating: "t", count: 32),
            session: URLSession(configuration: configuration),
            connectors: [AcceptanceConnector(item: item)]
        )

        _ = await sync.synchronize(
            seed: ResearchSyncSeed(
                sourceItems: [],
                sourceHealth: [],
                notifications: [],
                sourceBlocklist: [
                    SourceBlockRule(
                        domain: "arxiv.org",
                        label: "arxiv.org",
                        createdAt: item.collectedAt
                    ),
                ]
            )
        )

        let paths = await recorder.paths()
        XCTAssertEqual(paths, ["/v1/bootstrap"])
    }

    func testExistingBackendOpportunityReceivesNativeNotificationHistory() async throws {
        let item = SourceItem(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000077")!,
            group: .official,
            externalID: "native-notification-77",
            title: "Native notification release",
            summary: "Existing native notification history should become available to the web client.",
            author: "Official publisher",
            url: URL(string: "https://official.example/releases/77")!,
            publishedAt: Date(timeIntervalSince1970: 1_784_708_800),
            collectedAt: Date(timeIntervalSince1970: 1_784_709_100),
            language: "en",
            country: "US",
            topicKey: "native-notification-77",
            isOriginalSource: true,
            credibility: 1,
            engagement: 0,
            verification: .confirmed,
            dataTruth: .cached
        )
        let serverOpportunity = ResearchPipeline().run(items: [item], now: item.collectedAt).opportunities[0]
        let opportunity = Opportunity(
            id: serverOpportunity.id,
            topicKey: "native-client-topic-77",
            title: serverOpportunity.title,
            brief: serverOpportunity.brief,
            verification: serverOpportunity.verification,
            earliestPublishedAt: serverOpportunity.earliestPublishedAt,
            originalSource: serverOpportunity.originalSource,
            items: serverOpportunity.items,
            score: serverOpportunity.score,
            regionalExplanation: serverOpportunity.regionalExplanation,
            coverageExplanation: serverOpportunity.coverageExplanation,
            disposition: serverOpportunity.disposition
        )
        let notification = NotificationRecord(
            id: UUID(uuidString: "30000000-0000-4000-8000-000000000077")!,
            opportunityID: opportunity.id,
            title: opportunity.title,
            delivery: .immediate,
            createdAt: item.collectedAt,
            isRead: false
        )
        let recorder = RequestRecorder(item: item)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AcceptanceURLProtocol.self]
        AcceptanceURLProtocol.recorder = recorder
        let sync = BackendResearchSync(
            baseURL: URL(string: "https://backend.example")!,
            token: String(repeating: "t", count: 32),
            session: URLSession(configuration: configuration),
            connectors: []
        )

        _ = await sync.synchronize(
            seed: ResearchSyncSeed(
                sourceItems: [item],
                opportunities: [opportunity],
                sourceHealth: [],
                notifications: [notification],
                sourceBlocklist: []
            )
        )

        let paths = await recorder.paths()
        XCTAssertEqual(paths, ["/v1/bootstrap", "/v1/ingestion", "/v1/bootstrap"])
        let ingestion = try await recorder.ingestionJSON()
        let batches = try XCTUnwrap(ingestion["batches"] as? [[String: Any]])
        let uploadedNotification = try XCTUnwrap(batches.first?["notification"] as? [String: Any])
        XCTAssertEqual(batches.first?["clusterKey"] as? String, serverOpportunity.topicKey)
        XCTAssertEqual(uploadedNotification["title"] as? String, notification.title)
        XCTAssertEqual(uploadedNotification["delivery"] as? String, "Immediate")
        XCTAssertEqual(uploadedNotification["isRead"] as? Bool, false)
    }

    func testLargeStoryClusterIsSplitIntoRequestsBelowBackendBodyLimit() async throws {
        let base = Date(timeIntervalSince1970: 1_784_909_100)
        let items = (0..<10).map { index in
            SourceItem(
                id: UUID(),
                group: .official,
                externalID: "large-official-entry-\(index)",
                title: "Large official release \(index)",
                summary: String(repeating: "Evidence \(index) ", count: 700),
                author: "Official publisher",
                url: URL(string: "https://official.example/releases/large-\(index)")!,
                publishedAt: base.addingTimeInterval(TimeInterval(index)),
                collectedAt: base.addingTimeInterval(100),
                language: "en",
                country: "US",
                topicKey: "large-official-release",
                isOriginalSource: true,
                credibility: 1,
                engagement: index,
                verification: .confirmed,
                dataTruth: .live
            )
        }
        let connector = LargeAcceptanceConnector(items: items)
        let recorder = RequestRecorder(item: items[0])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AcceptanceURLProtocol.self]
        AcceptanceURLProtocol.recorder = recorder
        let sync = BackendResearchSync(
            baseURL: URL(string: "https://backend.example")!,
            token: String(repeating: "t", count: 32),
            session: URLSession(configuration: configuration),
            connectors: [connector]
        )

        let results = await sync.synchronize()

        XCTAssertEqual(results.first { $0.group == .official }?.state, .connected)
        let bodySizes = await recorder.ingestionBodySizes()
        XCTAssertGreaterThan(bodySizes.count, 1)
        XCTAssertTrue(bodySizes.allSatisfy { $0 < 64 * 1024 })
        let externalIDs = try await recorder.ingestedExternalIDs()
        XCTAssertEqual(externalIDs, Set(items.map(\.externalID)))
    }
}

private struct AcceptanceConnector: ProductionSourceConnector {
    let item: SourceItem
    let source = OfficialSource(
        id: "acceptance",
        name: "Acceptance Official Feed",
        kind: .rss,
        endpoint: URL(string: "https://official.example/feed.xml")!,
        homepage: URL(string: "https://official.example")!,
        language: "en",
        country: "US"
    )

    func collect() async -> ConnectorCollection {
        ConnectorCollection(
            items: [item], state: .available, validators: nil,
            collectedAt: item.collectedAt, evidence: "1 official item mapped."
        )
    }
}

private struct LargeAcceptanceConnector: ProductionSourceConnector {
    let items: [SourceItem]
    let source = OfficialSource(
        id: "large-acceptance",
        name: "Large Acceptance Official Feed",
        kind: .rss,
        endpoint: URL(string: "https://official.example/large-feed.xml")!,
        homepage: URL(string: "https://official.example")!,
        language: "en",
        country: "US"
    )

    func collect() async -> ConnectorCollection {
        ConnectorCollection(
            items: items,
            state: .available,
            validators: nil,
            collectedAt: items[0].collectedAt,
            evidence: "\(items.count) official items mapped."
        )
    }
}

private final class AcceptanceURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var recorder: RequestRecorder?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let recorder = Self.recorder else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let requestBody = request.httpBody ?? Self.readBody(request.httpBodyStream)
        Task {
            let (status, headers, body) = await recorder.response(for: request, body: requestBody)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    private static func readBody(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private actor RequestRecorder {
    private let item: SourceItem
    private let startsEmpty: Bool
    private var recordedPaths: [String] = []
    private var ingestionBodies: [Data] = []

    init(item: SourceItem, startsEmpty: Bool = false) {
        self.item = item
        self.startsEmpty = startsEmpty
    }

    func response(for request: URLRequest, body: Data) -> (Int, [String: String], Data) {
        recordedPaths.append(request.url!.path)
        if request.url!.path == "/v1/ingestion" {
            ingestionBodies.append(body)
            if body.count >= 64 * 1024 {
                return (413, [:], Data(#"{"error":"payload_too_large"}"#.utf8))
            }
            return (202, [:], Data(#"{"acceptedBatches":1,"opportunityIDs":["20000000-0000-4000-8000-000000000099"]}"#.utf8))
        }
        let formatter = ISO8601DateFormatter()
        let health = SourceGroup.allCases.map { group -> [String: Any] in
            [
                "group": group.rawValue,
                "state": group == .official ? "Connected" : "Setup required",
                "lastActivity": group == .official ? formatter.string(from: item.collectedAt) : NSNull(),
                "evidence": group == .official ? "1 live official item accepted." : "This source is not configured.",
                "repairAction": group == .official ? "Review" : "Configure",
                "dataTruth": group == .official ? "Live" : "Missing",
            ]
        }
        let apiItem: [String: Any] = [
            "id": item.id.uuidString,
            "group": item.group.rawValue,
            "externalID": item.externalID,
            "title": item.title,
            "summary": item.summary,
            "author": item.author,
            "url": item.url.absoluteString,
            "publishedAt": formatter.string(from: item.publishedAt),
            "collectedAt": formatter.string(from: item.collectedAt),
            "language": item.language,
            "country": item.country,
            "topicKey": item.topicKey,
            "isOriginalSource": item.isOriginalSource,
            "credibility": item.credibility,
            "engagement": item.engagement,
            "verification": item.verification.rawValue,
        ]
        let opportunity = ResearchPipeline().run(items: [item], now: item.collectedAt).opportunities[0]
        let apiOpportunity: [String: Any] = [
            "id": "20000000-0000-4000-8000-000000000099",
            "topicKey": opportunity.topicKey,
            "title": opportunity.title,
            "brief": opportunity.brief,
            "verification": opportunity.verification.rawValue,
            "earliestPublishedAt": formatter.string(from: opportunity.earliestPublishedAt),
            "originalSource": apiItem,
            "items": [apiItem],
            "score": [
                "freshness": opportunity.score.freshness,
                "credibility": opportunity.score.credibility,
                "momentum": opportunity.score.momentum,
                "creatorActivity": opportunity.score.creatorActivity,
                "arabicCoverageGap": opportunity.score.arabicCoverageGap,
                "regionalRelevance": opportunity.score.regionalRelevance,
            ],
            "regionalExplanation": opportunity.regionalExplanation,
            "coverageExplanation": opportunity.coverageExplanation,
            "disposition": opportunity.disposition.rawValue,
            "dispositionUpdatedAt": formatter.string(from: item.collectedAt),
            "dispositionMutationID": NSNull(),
            "isHighPriority": opportunity.isHighPriority,
        ]
        let opportunities: [[String: Any]] = startsEmpty && ingestionBodies.isEmpty ? [] : [apiOpportunity]
        let body = try! JSONSerialization.data(withJSONObject: [
            "sourceHealth": health,
            "opportunities": opportunities,
            "watchlist": [],
            "notifications": [],
        ])
        return (200, ["ETag": "\"acceptance-1\""], body)
    }

    func paths() -> [String] { recordedPaths }

    func ingestionJSON() throws -> [String: Any] {
        let ingestion = try XCTUnwrap(ingestionBodies.first)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: ingestion) as? [String: Any])
    }

    func ingestionBodySizes() -> [Int] { ingestionBodies.map(\.count) }

    func ingestedExternalIDs() throws -> Set<String> {
        try ingestionBodies.reduce(into: []) { result, body in
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let batches = try XCTUnwrap(json["batches"] as? [[String: Any]])
            for batch in batches {
                let items = try XCTUnwrap(batch["sourceItems"] as? [[String: Any]])
                result.formUnion(items.compactMap { $0["externalID"] as? String })
            }
        }
    }
}
