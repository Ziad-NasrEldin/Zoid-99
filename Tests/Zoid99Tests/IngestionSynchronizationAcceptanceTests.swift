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
    private var recordedPaths: [String] = []
    private var ingestion = Data()

    init(item: SourceItem) {
        self.item = item
    }

    func response(for request: URLRequest, body: Data) -> (Int, [String: String], Data) {
        recordedPaths.append(request.url!.path)
        if request.url!.path == "/v1/ingestion" {
            ingestion = body
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
        let body = try! JSONSerialization.data(withJSONObject: [
            "sourceHealth": health,
            "opportunities": [["items": [apiItem]]],
            "watchlist": [],
            "notifications": [],
        ])
        return (200, ["ETag": "\"acceptance-1\""], body)
    }

    func paths() -> [String] { recordedPaths }

    func ingestionJSON() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: ingestion) as? [String: Any])
    }
}
