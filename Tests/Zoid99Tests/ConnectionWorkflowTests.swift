import Foundation
import XCTest
@testable import Zoid99

@MainActor
final class ConnectionWorkflowTests: XCTestCase {
    func testCatalogHasTruthfulCredentialBoundariesAndNoAppAccountProvider() {
        XCTAssertEqual(Set(ProviderDefinition.catalog.map(\.provider)), Set(ExternalProvider.allCases))
        XCTAssertEqual(definition(.youtube).credentialBoundary, .keychain)
        XCTAssertEqual(definition(.meta).credentialBoundary, .keychain)
        XCTAssertEqual(definition(.x).credentialBoundary, .keychain)
        XCTAssertEqual(definition(.googleTrends).credentialBoundary, .serverSecret)
        XCTAssertEqual(definition(.aiProvider).credentialBoundary, .serverSecret)
        XCTAssertEqual(definition(.officialFeeds).credentialBoundary, .none)
        XCTAssertFalse(ProviderDefinition.catalog.map(\.setupGuidance).joined().localizedCaseInsensitiveContains("Zoid 99 account"))
    }

    func testKeychainBoundaryNeverStoresCredentialWithoutProviderVerification() async {
        let credentials = MemoryCredentialStore()
        let service = LocalProviderConnectionService(
            credentials: credentials,
            validator: SetupRequiredProviderValidator(),
            now: { Date(timeIntervalSince1970: 1_785_000_000) }
        )

        let result = await service.connect(.youtube, credential: "fixture-secret")

        XCTAssertEqual(result.state, .unavailable)
        XCTAssertTrue(result.evidence.contains("validator is required"))
        XCTAssertFalse(result.evidence.contains("fixture-secret"))
        XCTAssertFalse(try! credentials.contains(provider: .youtube))
    }

    func testOfficialValidatorAcceptsProviderReadAccessWithoutLeakingCredentials() async {
        let transport = ConnectionHTTPTransport(responses: [
            HTTPResponse(statusCode: 200, headers: [:], body: Data("{}".utf8)),
            HTTPResponse(
                statusCode: 200,
                headers: [:],
                body: Data(#"{"data":[{"instagram_business_account":{"id":"1"}}]}"#.utf8)
            ),
            HTTPResponse(statusCode: 200, headers: [:], body: Data("{}".utf8)),
        ])
        let validator = OfficialProviderCredentialValidator(transport: transport)

        let youtube = await validator.validate(.youtube, credential: "youtube-secret")
        let instagram = await validator.validate(.meta, credential: "instagram-secret")
        let x = await validator.validate(.x, credential: "x-secret")
        let requests = await transport.requests

        XCTAssertEqual([youtube.state, instagram.state, x.state], [.connected, .connected, .connected])
        XCTAssertFalse([youtube, instagram, x].map(\.evidence).joined().contains("secret"))
        XCTAssertTrue(requests[0].url.absoluteString.contains("youtube/v3/videos"))
        XCTAssertEqual(requests[1].headers["Authorization"], "Bearer instagram-secret")
        XCTAssertEqual(requests[2].headers["Authorization"], "Bearer x-secret")
    }

    func testProviderValidationFailureDoesNotStoreSubmittedCredential() async {
        let credentials = MemoryCredentialStore()
        let transport = ConnectionHTTPTransport(responses: [
            HTTPResponse(statusCode: 403, headers: [:], body: Data())
        ])
        let service = LocalProviderConnectionService(
            credentials: credentials,
            validator: OfficialProviderCredentialValidator(transport: transport)
        )

        let result = await service.connect(.youtube, credential: "rejected-secret")

        XCTAssertEqual(result.state, .setupRequired)
        XCTAssertFalse(result.evidence.contains("rejected-secret"))
        XCTAssertFalse(try! credentials.contains(provider: .youtube))
    }

    func testLocalResearchSyncCollectsOfficialFeedsWithoutBackendCredentials() async throws {
        let item = try XCTUnwrap(ResearchFixtures.allSix.first { $0.group == .official })
        let connector = FixtureProductionConnector(
            collection: ConnectorCollection(
                items: [item],
                state: .available,
                validators: nil,
                collectedAt: item.collectedAt,
                evidence: "1 published item mapped from a credential-free official source."
            )
        )
        let sync = LocalResearchSync(officialConnectors: [connector], environment: [:])

        let results = await sync.synchronize()

        XCTAssertEqual(results.first { $0.group == .official }?.state, .connected)
        XCTAssertEqual(results.first { $0.group == .official }?.items, [item])
        XCTAssertEqual(results.first { $0.group == .googleTrends }?.state, .unsupported)
        XCTAssertEqual(results.first { $0.group == .comments }?.state, .setupRequired)
    }

    func testLocalGoogleTrendsRemainsUnsupportedWithoutApprovedOfficialAccess() async {
        let sync = LocalResearchSync(officialConnectors: [], environment: [:])
        let results = await sync.synchronize(watchlist: [
            WatchlistEntry(id: UUID(), kind: .topic, value: "AI agents", highPriority: true)
        ])

        let trends = results.first { $0.group == .googleTrends }
        XCTAssertEqual(trends?.state, .unsupported)
        XCTAssertEqual(trends?.dataTruth, .unavailable)
        XCTAssertTrue(trends?.items.isEmpty == true)
        XCTAssertTrue(trends?.evidence.contains("apply for Google Trends API alpha access") == true)
    }

    func testVerifiedCredentialIsStoredAndMarkedConnected() async {
        let credentials = MemoryCredentialStore()
        let service = LocalProviderConnectionService(
            credentials: credentials,
            validator: ConnectedCredentialValidator()
        )

        let result = await service.connect(.youtube, credential: "verified-fixture-secret")

        XCTAssertEqual(result.state, .connected)
        XCTAssertTrue(try! credentials.contains(provider: .youtube))
        XCTAssertFalse(result.evidence.contains("verified-fixture-secret"))
    }

    func testServerSecretIsRejectedByNativeClientBoundary() async {
        let credentials = MemoryCredentialStore()
        let service = LocalProviderConnectionService(credentials: credentials)

        let result = await service.connect(.aiProvider, credential: "must-not-be-stored")

        XCTAssertEqual(result.state, .setupRequired)
        XCTAssertFalse(try! credentials.contains(provider: .aiProvider))
        XCTAssertFalse(result.evidence.contains("must-not-be-stored"))
    }

    func testDisconnectRetainsLastActivityAndEvidenceBecomesExplicit() async {
        let checkedAt = Date(timeIntervalSince1970: 1_785_000_000)
        let service = FixtureConnectionService(results: [
            .youtube: ProviderValidationResult(
                state: .disconnected,
                evidence: "Local authorization was removed. Previously collected evidence remains available.",
                checkedAt: checkedAt,
                retryAt: nil
            )
        ])
        let store = AppStore(
            persistence: ConnectionMemoryPersistence(),
            connectionService: service
        )
        let previousActivity = store.providerConnections.first { $0.provider == .youtube }?.lastActivity

        await store.disconnect(.youtube)

        let connection = try! XCTUnwrap(store.providerConnections.first { $0.provider == .youtube })
        XCTAssertEqual(connection.state, .disconnected)
        XCTAssertEqual(connection.lastActivity, previousActivity)
        XCTAssertTrue(connection.evidence.contains("Previously collected evidence remains"))
    }

    func testFailedRefreshRetainsPreviousActivityAndEvidence() async {
        let persistence = ConnectionMemoryPersistence()
        let initialStore = AppStore(persistence: persistence)
        let original = try! XCTUnwrap(initialStore.sourceHealth.first { $0.group == .official })
        let sync = ConnectionStubSync(results: [
            SourceSyncResult(
                group: .official,
                collectedAt: Date(timeIntervalSince1970: 1_785_000_000),
                items: [],
                state: .unavailable,
                dataTruth: .unavailable,
                evidence: "The endpoint returned 503."
            )
        ])
        let store = AppStore(persistence: persistence, sync: sync)

        await store.refresh()
        await store.refresh()

        let repaired = try! XCTUnwrap(store.sourceHealth.first { $0.group == .official })
        XCTAssertEqual(repaired.lastActivity, original.lastActivity)
        XCTAssertTrue(repaired.evidence.contains("The endpoint returned 503."))
        XCTAssertTrue(repaired.evidence.contains("Last known evidence:"))
        XCTAssertEqual(repaired.evidence.components(separatedBy: "Last known evidence:").count - 1, 1)
        XCTAssertEqual(store.sourceHealth.count, SourceGroup.allCases.count)
    }

    private func definition(_ provider: ExternalProvider) -> ProviderDefinition {
        ProviderDefinition.catalog.first { $0.provider == provider }!
    }
}

private final class MemoryCredentialStore: CredentialStoring, @unchecked Sendable {
    private var providers = Set<ExternalProvider>()
    private var values: [ExternalProvider: String] = [:]

    func contains(provider: ExternalProvider) throws -> Bool {
        providers.contains(provider)
    }

    func credential(provider: ExternalProvider) throws -> String? {
        values[provider]
    }

    func set(_ credential: String, provider: ExternalProvider) throws {
        providers.insert(provider)
        values[provider] = credential
    }

    func remove(provider: ExternalProvider) throws {
        providers.remove(provider)
        values.removeValue(forKey: provider)
    }
}

private struct ConnectedCredentialValidator: ProviderCredentialValidating {
    func validate(_ provider: ExternalProvider, credential: String?) async -> ProviderValidationResult {
        ProviderValidationResult(
            state: .connected,
            evidence: "The fixture provider accepted the validation request.",
            checkedAt: Date(timeIntervalSince1970: 1_785_000_000),
            retryAt: nil
        )
    }
}

private actor ConnectionHTTPTransport: HTTPTransport {
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

private struct FixtureProductionConnector: ProductionSourceConnector {
    let source = OfficialAISourceCatalog.starter[0]
    let collection: ConnectorCollection

    func collect() async -> ConnectorCollection {
        collection
    }
}

private actor FixtureConnectionService: ProviderConnectionServicing {
    let results: [ExternalProvider: ProviderValidationResult]

    init(results: [ExternalProvider: ProviderValidationResult]) {
        self.results = results
    }

    func validate(_ provider: ExternalProvider) async -> ProviderValidationResult {
        result(provider)
    }

    func connect(_ provider: ExternalProvider, credential: String?) async -> ProviderValidationResult {
        result(provider)
    }

    func disconnect(_ provider: ExternalProvider) async -> ProviderValidationResult {
        result(provider)
    }

    private func result(_ provider: ExternalProvider) -> ProviderValidationResult {
        results[provider] ?? ProviderValidationResult(
            state: .unsupported,
            evidence: "No fixture result.",
            checkedAt: .distantPast,
            retryAt: nil
        )
    }
}

private final class ConnectionMemoryPersistence: ResearchPersistence, @unchecked Sendable {
    private var state: ResearchState?

    func load() throws -> ResearchState? { state }
    func save(_ state: ResearchState) throws { self.state = state }
}

private struct ConnectionStubSync: ResearchSyncing {
    let results: [SourceSyncResult]
    func synchronize() async -> [SourceSyncResult] { results }
}
