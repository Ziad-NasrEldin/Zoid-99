import Foundation
import XCTest
@testable import Zoid99

final class SyncCompatibilityTests: XCTestCase {
    func testWebPaginatedDispositionStateReachesMac() async throws {
        let transport = FixtureHTTPTransport(responses: [
            try response(named: "dispositions-page-1"),
            try response(named: "dispositions-page-2")
        ])
        let sync = BackendOpportunityDispositionSync(
            baseURL: URL(string: "https://backend.example")!,
            apiToken: String(repeating: "t", count: 32),
            transport: transport
        )

        let result = await sync.reconcile([])
        let states = result.states.sorted { $0.opportunityID.uuidString < $1.opportunityID.uuidString }
        let requests = await transport.requests

        XCTAssertNil(result.errorMessage)
        XCTAssertEqual(states.map(\.disposition), [.dismissed, .watched])
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].url.path, "/v1/opportunities")
        XCTAssertTrue(requests[0].url.query?.contains("limit=200") == true)
        XCTAssertTrue(requests[1].url.query?.contains("cursor=page-2") == true)
    }

    func testMacDispositionMutationReconcilesAgainstCanonicalWebState() async throws {
        let transport = FixtureHTTPTransport(responses: [
            try response(named: "disposition-mac"),
            try response(named: "dispositions-page-1"),
            try response(named: "dispositions-page-2")
        ])
        let sync = BackendOpportunityDispositionSync(
            baseURL: URL(string: "https://backend.example")!,
            apiToken: String(repeating: "t", count: 32),
            transport: transport
        )
        let mutation = OpportunityDispositionMutation(
            id: UUID(uuidString: "50000000-0000-4000-8000-000000000003")!,
            opportunityID: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!,
            disposition: .saved,
            changedAt: Date(timeIntervalSince1970: 1_785_250_800)
        )

        let result = await sync.reconcile([mutation])
        let requests = await transport.requests
        let requestBody = try XCTUnwrap(requests.first?.body)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])

        XCTAssertNil(result.errorMessage)
        XCTAssertEqual(result.acknowledgedMutationIDs, Set([mutation.id]))
        XCTAssertEqual(body["mutationID"] as? String, mutation.id.uuidString)
        XCTAssertEqual(requests.first?.headers["Authorization"], "Bearer \(String(repeating: "t", count: 32))")
    }

    func testServerCanonicalPreferencesReachMacAndMacPatchUsesETag() async throws {
        let transport = FixtureHTTPTransport(responses: [
            try response(named: "preferences-web", headers: ["ETag": "\"preferences-v7\""]),
            try response(named: "preferences-web", headers: ["ETag": "\"preferences-v8\""])
        ])
        let sync = BackendPreferenceSync(
            baseURL: URL(string: "https://backend.example")!,
            apiToken: String(repeating: "t", count: 32),
            transport: transport
        )

        let canonical = await sync.fetchCanonical()
        let updated = await sync.update(
            ServerPreferencePatch(refreshMinutes: 45),
            ifMatch: try XCTUnwrap(canonical.etag),
            idempotencyKey: "preferences-update-1"
        )
        let requests = await transport.requests
        let body = try XCTUnwrap(requests[1].body)

        XCTAssertEqual(canonical.preferences?.refreshMinutes, 30)
        XCTAssertEqual(canonical.etag, "\"preferences-v7\"")
        XCTAssertEqual(updated.preferences?.digestHour, 19)
        XCTAssertEqual(requests[1].headers["If-Match"], "\"preferences-v7\"")
        let expectedBody = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL(named: "preferences-mac"))) as? [String: Any]
        )
        let actualBody = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(actualBody["refreshMinutes"] as? Int, expectedBody["refreshMinutes"] as? Int)
        XCTAssertEqual(requests[1].headers["Idempotency-Key"], "preferences-update-1")
    }

    func testPreferenceWriteUsesCallerStableIdempotencyKey() async throws {
        let transport = FixtureHTTPTransport(responses: [
            try response(named: "preferences-web", headers: ["ETag": "\"preferences-v8\""]),
            try response(named: "preferences-web", headers: ["ETag": "\"preferences-v9\""])
        ])
        let sync = BackendPreferenceSync(
            baseURL: URL(string: "https://backend.example")!,
            apiToken: String(repeating: "t", count: 32),
            transport: transport
        )
        let patch = ServerPreferencePatch(refreshMinutes: 45)

        _ = await sync.update(patch, ifMatch: "\"preferences-v7\"", idempotencyKey: "preference-retry-1")
        _ = await sync.update(patch, ifMatch: "\"preferences-v7\"", idempotencyKey: "preference-retry-1")

        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.headers["Idempotency-Key"] }, ["preference-retry-1", "preference-retry-1"])
    }

    @MainActor
    func testWebCanonicalPreferencesUpdateTheMacStore() async throws {
        let transport = FixtureHTTPTransport(responses: [
            try response(named: "preferences-web", headers: ["ETag": "\"preferences-v7\""])
        ])
        let store = AppStore(
            persistence: PreferencePersistenceProbe(),
            sync: NoopResearchSync(),
            dispositionSync: NoopOpportunityDispositionSync(),
            watchlistSync: NoopWatchlistSync(),
            preferenceSync: BackendPreferenceSync(
                baseURL: URL(string: "https://backend.example")!,
                apiToken: String(repeating: "t", count: 32),
                transport: transport
            ),
            loadDemoDataWhenEmpty: false
        )

        await store.synchronizePreferences()

        let requests = await transport.requests
        XCTAssertEqual(store.refreshMinutes, 30)
        XCTAssertEqual(store.digestHour, 19)
        XCTAssertEqual(requests.first?.headers["Authorization"], "Bearer \(String(repeating: "t", count: 32))")
    }

    @MainActor
    func testOfflineMacPreferencePatchSurvivesPersistenceAndRetries() async {
        let persistence = PreferencePersistenceProbe()
        let sync = OfflineThenOnlinePreferenceSync()
        let store = AppStore(
            persistence: persistence,
            sync: NoopResearchSync(),
            dispositionSync: NoopOpportunityDispositionSync(),
            watchlistSync: NoopWatchlistSync(),
            preferenceSync: sync,
            loadDemoDataWhenEmpty: false
        )

        store.setRefreshMinutes(45)
        await Task.yield()
        XCTAssertEqual(persistence.preferenceState?.pendingPatch.refreshMinutes, 45)

        sync.online = true
        await store.synchronizePreferences()

        XCTAssertEqual(store.refreshMinutes, 45)
        XCTAssertTrue(persistence.preferenceState?.pendingPatch.isEmpty == true)
    }

    @MainActor
    func testPreferenceConflictRetryReusesPersistedIdempotencyKey() async {
        let persistence = PreferencePersistenceProbe()
        let sync = OfflineThenOnlinePreferenceSync()
        let store = AppStore(
            persistence: persistence,
            sync: NoopResearchSync(),
            dispositionSync: NoopOpportunityDispositionSync(),
            watchlistSync: NoopWatchlistSync(),
            preferenceSync: sync,
            loadDemoDataWhenEmpty: false
        )

        store.setRefreshMinutes(45)
        await Task.yield()
        guard let pendingKey = persistence.preferenceState?.idempotencyKey else {
            XCTFail("Preference mutation key was not persisted")
            return
        }

        sync.online = true
        sync.conflictNext = true
        await store.synchronizePreferences()

        XCTAssertEqual(sync.updateKeys, [pendingKey, pendingKey])
        XCTAssertTrue(persistence.preferenceState?.pendingPatch.isEmpty == true)
    }

    private func response(named name: String, headers: [String: String] = [:]) throws -> HTTPResponse {
        HTTPResponse(statusCode: 200, headers: headers, body: try Data(contentsOf: fixtureURL(named: name)))
    }

    private func fixtureURL(named name: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
    }
}

private actor FixtureHTTPTransport: HTTPTransport {
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

private final class PreferencePersistenceProbe: ResearchPersistence, PreferenceSyncStatePersistence, @unchecked Sendable {
    var state: ResearchState?
    var preferenceState: PreferenceSyncState?

    func load() throws -> ResearchState? { state }

    func save(_ state: ResearchState) throws {
        self.state = state
    }

    func loadPreferenceSyncState() throws -> PreferenceSyncState? {
        preferenceState
    }

    func savePreferenceSyncState(_ state: PreferenceSyncState) throws {
        preferenceState = state
    }
}

@MainActor
private final class OfflineThenOnlinePreferenceSync: PreferenceSyncing, @unchecked Sendable {
    var online = false
    var conflictNext = false
    private(set) var updateKeys: [String] = []
    private let canonical = ServerPreferences(
        refreshMinutes: 45,
        notificationsEnabled: false,
        digestHour: 19,
        quietHours: ServerQuietHours(enabled: true, start: "22:30", end: "08:15"),
        locale: "en",
        timeZone: "Africa/Cairo",
        updatedAt: Date(timeIntervalSince1970: 1_785_214_800)
    )

    func fetchCanonical() async -> PreferenceSyncResult {
        online
            ? PreferenceSyncResult(preferences: canonical, etag: "\"preferences-v9\"", conflict: false, errorMessage: nil)
            : PreferenceSyncResult(preferences: nil, etag: nil, conflict: false, errorMessage: "offline")
    }

    func update(
        _ patch: ServerPreferencePatch,
        ifMatch etag: String,
        idempotencyKey: String
    ) async -> PreferenceSyncResult {
        updateKeys.append(idempotencyKey)
        if conflictNext {
            conflictNext = false
            return PreferenceSyncResult(preferences: canonical, etag: "\"preferences-v9\"", conflict: true, errorMessage: "conflict")
        }
        return online
            ? PreferenceSyncResult(preferences: canonical, etag: "\"preferences-v10\"", conflict: false, errorMessage: nil)
            : PreferenceSyncResult(preferences: nil, etag: nil, conflict: false, errorMessage: "offline")
    }
}
