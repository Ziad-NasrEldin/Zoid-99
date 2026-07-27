import XCTest
@testable import Zoid99

final class DiscordNotificationTests: XCTestCase {
    func testValidationAcceptsOnlyCanonicalDiscordWebhookURLs() {
        XCTAssertNoThrow(
            try DiscordWebhookValidator.validate(makeWebhook())
        )
        XCTAssertThrowsError(
            try DiscordWebhookValidator.validate(makeWebhook(host: "example.com"))
        )
        XCTAssertThrowsError(
            try DiscordWebhookValidator.validate(makeWebhook(scheme: "http"))
        )
    }

    func testConfigurationValidatesBeforeSavingAndNeverReflectsSecret() async throws {
        let secret = canonicalWebhook
        let store = MemoryDiscordStore()
        let transport = RecordingDiscordTransport(responses: [
            HTTPResponse(statusCode: 200, headers: [:], body: Data())
        ])
        let service = DiscordNotificationService(store: store, transport: transport)

        try await service.configure(secret)

        XCTAssertEqual(store.current, secret)
        XCTAssertEqual(transport.requests.map(\.method), ["GET"])
        XCTAssertFalse(DiscordWebhookValidator.redactedDescription(configured: true).contains(secret))
        XCTAssertFalse(DiscordWebhookValidator.redactedDescription(configured: true).contains("123456789012345678"))
    }

    func testRejectedWebhookIsNotStored() async {
        let store = MemoryDiscordStore()
        let transport = RecordingDiscordTransport(responses: [
            HTTPResponse(statusCode: 404, headers: [:], body: Data())
        ])
        let service = DiscordNotificationService(store: store, transport: transport)

        await XCTAssertThrowsErrorAsync {
            try await service.configure(self.canonicalWebhook)
        }

        XCTAssertNil(store.current)
    }

    func testWebhookCanBeRotatedAndRemovedThroughStorageBoundary() throws {
        let store = MemoryDiscordStore()
        try store.setWebhook("first")
        try store.setWebhook("second")
        XCTAssertEqual(try store.webhook(), "second")
        try store.removeWebhook()
        XCTAssertFalse(try store.containsWebhook())
    }

    func testKeychainBoundaryUsesStableDedicatedIdentifiers() {
        XCTAssertEqual(KeychainDiscordWebhookStore.service, "com.ziadnasreldin.zoid99.discord")
        XCTAssertEqual(KeychainDiscordWebhookStore.account, "notification-webhook")
    }

    func testFormattingIncludesRequiredResearchFieldsAndOnlySafeHTTPSLink() {
        let message = DiscordOpportunityMessage.format(opportunity())
        let unsafeMessage = DiscordOpportunityMessage.format(
            opportunity(sourceURL: URL(string: "https://user:password@example.com/private")!)
        )

        XCTAssertTrue(message.content.contains("Zoid 99"))
        XCTAssertTrue(message.content.contains("New research opportunity"))
        XCTAssertTrue(message.content.contains("Score 90"))
        XCTAssertTrue(message.content.contains("Source: OpenAI"))
        XCTAssertTrue(message.content.contains("Reason: Arabic coverage remains limited."))
        XCTAssertTrue(message.content.contains("https://openai.com/research/example"))
        XCTAssertFalse(message.content.contains("credential"))
        XCTAssertFalse(unsafeMessage.content.contains("password"))
    }

    func testDisabledAndPreviouslyDeliveredOpportunitiesAreNotSent() async {
        let opportunity = opportunity()
        let service = RecordingDiscordService(configured: true)
        let coordinator = DiscordNotificationCoordinator(service: service)

        _ = await coordinator.process(
            opportunities: [opportunity],
            enabled: false,
            deliveredOpportunityIDs: []
        )
        _ = await coordinator.process(
            opportunities: [opportunity],
            enabled: true,
            deliveredOpportunityIDs: [opportunity.id]
        )

        let messageCount = await service.messages.count
        XCTAssertEqual(messageCount, 0)
    }

    func testSuccessfulDeliveryProducesDurableDeduplicationID() async {
        let opportunity = opportunity()
        let service = RecordingDiscordService(configured: true)
        let coordinator = DiscordNotificationCoordinator(service: service)

        let first = await coordinator.process(
            opportunities: [opportunity],
            enabled: true,
            deliveredOpportunityIDs: []
        )
        _ = await coordinator.process(
            opportunities: [opportunity],
            enabled: true,
            deliveredOpportunityIDs: first.deliveredOpportunityIDs
        )

        let messageCount = await service.messages.count
        XCTAssertEqual(messageCount, 1)
        XCTAssertEqual(first.deliveredOpportunityIDs, [opportunity.id])
    }

    func testStandardPriorityLiveOpportunityIsDelivered() async {
        let standardPriority = opportunity(score: standardScore)
        let service = RecordingDiscordService(configured: true)
        let coordinator = DiscordNotificationCoordinator(service: service)

        let result = await coordinator.process(
            opportunities: [standardPriority],
            enabled: true,
            deliveredOpportunityIDs: []
        )

        let messages = await service.messages
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0].content.contains("Priority: Standard"))
        XCTAssertEqual(result.deliveredOpportunityIDs, [standardPriority.id])
    }

    @MainActor
    func testRefreshDeliversNewOpportunityOnceAcrossRefreshAndRelaunch() async throws {
        let source = try XCTUnwrap(opportunity(score: standardScore).items.first)
        let result = SourceSyncResult(
            group: source.group,
            collectedAt: source.collectedAt,
            items: [source],
            state: .connected,
            dataTruth: .live,
            evidence: "One new live opportunity."
        )
        let persistence = DiscordMemoryPersistence()
        let service = RecordingDiscordService(configured: true)
        let sync = DiscordResearchSync(refreshResults: [result])
        let store = AppStore(
            persistence: persistence,
            sync: sync,
            discordService: service,
            loadDemoDataWhenEmpty: false
        )
        await store.refreshDiscordConfigurationStatus()
        store.setDiscordEnabled(true)

        await store.refresh()
        await store.refresh()

        var messages = await service.messages
        XCTAssertEqual(messages.count, 1)

        let restarted = AppStore(
            persistence: persistence,
            sync: sync,
            discordService: service,
            loadDemoDataWhenEmpty: false
        )
        await restarted.refreshDiscordConfigurationStatus()
        restarted.setDiscordEnabled(true)
        await restarted.refresh()

        messages = await service.messages
        XCTAssertEqual(messages.count, 1)
    }

    @MainActor
    func testManualTopicResearchDeliversNewOpportunity() async throws {
        let source = try XCTUnwrap(opportunity(score: standardScore).items.first)
        let result = SourceSyncResult(
            group: source.group,
            collectedAt: source.collectedAt,
            items: [source],
            state: .connected,
            dataTruth: .live,
            evidence: "Topic research found one new opportunity."
        )
        let service = RecordingDiscordService(configured: true)
        let store = AppStore(
            persistence: DiscordMemoryPersistence(),
            sync: DiscordResearchSync(topicResults: [result]),
            discordService: service,
            loadDemoDataWhenEmpty: false
        )
        await store.refreshDiscordConfigurationStatus()
        store.setDiscordEnabled(true)

        await store.researchTopicAcrossConnectedSources("model release")

        let messages = await service.messages
        XCTAssertEqual(messages.count, 1)
    }

    func testDiscordDeliveryRemainsIndependentWhenNativeNotificationsAreDisabled() async {
        let opportunity = opportunity()
        let service = RecordingDiscordService(configured: true)
        let coordinator = DiscordNotificationCoordinator(service: service)

        let result = await coordinator.process(
            opportunities: [opportunity],
            enabled: true,
            deliveredOpportunityIDs: []
        )

        let messageCount = await service.messages.count
        XCTAssertEqual(messageCount, 1)
        XCTAssertEqual(result.deliveredOpportunityIDs, [opportunity.id])
    }

    func testRateLimitRetriesAreBoundedAndHonorCappedRetryAfter() async throws {
        let store = MemoryDiscordStore(current: canonicalWebhook)
        let transport = RecordingDiscordTransport(responses: [
            HTTPResponse(statusCode: 429, headers: ["Retry-After": "90"], body: Data()),
            HTTPResponse(statusCode: 429, headers: ["Retry-After": "0.1"], body: Data()),
            HTTPResponse(statusCode: 204, headers: [:], body: Data()),
        ])
        let delays = DelayRecorder()
        let service = DiscordNotificationService(
            store: store,
            transport: transport,
            maximumAttempts: 3,
            sleeper: { await delays.append($0) }
        )

        try await service.send(.test)

        XCTAssertEqual(transport.requests.count, 3)
        let recordedDelays = await delays.values
        XCTAssertEqual(recordedDelays, [30, 0.25])
    }

    func testPayloadDisablesMentionsAndDoesNotContainWebhook() async throws {
        let store = MemoryDiscordStore(current: canonicalWebhook)
        let transport = RecordingDiscordTransport(responses: [
            HTTPResponse(statusCode: 204, headers: [:], body: Data())
        ])
        let service = DiscordNotificationService(store: store, transport: transport)

        try await service.send(.test)

        let body = try XCTUnwrap(transport.requests.first?.body)
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.contains("\"parse\":[]"))
        XCTAssertFalse(text.contains(canonicalWebhook))
        XCTAssertFalse(text.contains("123456789012345678"))
    }

    private var canonicalWebhook: String {
        makeWebhook()
    }

    private func makeWebhook(
        scheme: String = "https",
        host: String = "discord.com"
    ) -> String {
        "\(scheme)://\(host)/api/" + "webhooks/"
            + String(repeating: "1", count: 18) + "/"
            + String(repeating: "a", count: 26)
    }

    private var standardScore: ScoreBreakdown {
        ScoreBreakdown(
            freshness: 5,
            credibility: 5,
            momentum: 5,
            creatorActivity: 5,
            arabicCoverageGap: 5,
            regionalRelevance: 5
        )
    }

    private func opportunity(
        sourceURL: URL = URL(string: "https://openai.com/research/example")!,
        score: ScoreBreakdown = ScoreBreakdown(
            freshness: 15,
            credibility: 20,
            momentum: 15,
            creatorActivity: 10,
            arabicCoverageGap: 15,
            regionalRelevance: 15
        )
    ) -> Opportunity {
        let source = SourceItem(
            id: UUID(),
            group: .official,
            externalID: "official-1",
            title: "Official release",
            summary: "Public release evidence.",
            author: "OpenAI",
            url: sourceURL,
            publishedAt: Date(timeIntervalSince1970: 100),
            collectedAt: Date(timeIntervalSince1970: 110),
            language: "en",
            country: "US",
            topicKey: "release",
            isOriginalSource: true,
            credibility: 1,
            engagement: 10,
            verification: .confirmed,
            dataTruth: .live
        )
        return Opportunity(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000009999")!,
            topicKey: "release",
            title: "Confirmed model release",
            brief: "A verified release.",
            verification: .confirmed,
            earliestPublishedAt: source.publishedAt,
            originalSource: source,
            items: [source],
            score: score,
            regionalExplanation: "Relevant to Egypt and the Gulf.",
            coverageExplanation: "Arabic coverage remains limited.",
            disposition: .active
        )
    }
}

private final class DiscordMemoryPersistence: ResearchPersistence, @unchecked Sendable {
    private let lock = NSLock()
    private var state: ResearchState?

    func load() throws -> ResearchState? {
        lock.withLock { state }
    }

    func save(_ state: ResearchState) throws {
        lock.withLock { self.state = state }
    }
}

private struct DiscordResearchSync: ResearchSyncing {
    var refreshResults: [SourceSyncResult] = []
    var topicResults: [SourceSyncResult] = []

    func synchronize() async -> [SourceSyncResult] {
        refreshResults
    }

    func researchTopic(_ query: String, watchlist: [WatchlistEntry]) async -> [SourceSyncResult] {
        topicResults
    }
}

private final class MemoryDiscordStore: DiscordWebhookStoring, @unchecked Sendable {
    var current: String?

    init(current: String? = nil) {
        self.current = current
    }

    func containsWebhook() throws -> Bool { current != nil }
    func webhook() throws -> String? { current }
    func setWebhook(_ value: String) throws { current = value }
    func removeWebhook() throws { current = nil }
}

private final class RecordingDiscordTransport: HTTPTransport, @unchecked Sendable {
    private var responses: [HTTPResponse]
    private(set) var requests: [HTTPRequest] = []

    init(responses: [HTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        return responses.removeFirst()
    }
}

private actor RecordingDiscordService: DiscordNotificationServicing {
    let configured: Bool
    var messages: [DiscordOpportunityMessage] = []

    init(configured: Bool) {
        self.configured = configured
    }

    func isConfigured() async -> Bool { configured }
    func configure(_ value: String) async throws {}
    func remove() async throws {}
    func send(_ message: DiscordOpportunityMessage) async throws { messages.append(message) }
}

private actor DelayRecorder {
    var values: [TimeInterval] = []
    func append(_ value: TimeInterval) { values.append(value) }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {}
}
