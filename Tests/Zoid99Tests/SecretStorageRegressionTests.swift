import XCTest
@testable import Zoid99

final class SecretStorageRegressionTests: XCTestCase {
    func testProviderCredentialIsEphemeralToTheLiveSession() throws {
        let firstSession = InMemoryCredentialStore()
        try firstSession.set("session-only-provider-secret", provider: .youtube)

        XCTAssertEqual(try firstSession.credential(provider: .youtube), "session-only-provider-secret")
        XCTAssertNil(try InMemoryCredentialStore().credential(provider: .youtube))
    }

    func testDiscordWebhookIsEphemeralToTheLiveSession() throws {
        let firstSession = InMemoryDiscordWebhookStore()
        try firstSession.setWebhook("https://discord.com/api/webhooks/session-only")

        XCTAssertTrue(try firstSession.containsWebhook())
        XCTAssertNil(try InMemoryDiscordWebhookStore().webhook())
    }
}
