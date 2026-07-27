import Foundation
import Security

enum DiscordWebhookError: Error, Equatable, LocalizedError {
    case invalidURL
    case notConfigured
    case rejected
    case rateLimited(retryAfter: TimeInterval?)
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Enter a valid Discord webhook URL."
        case .notConfigured: "No Discord webhook is saved."
        case .rejected: "Discord rejected this webhook. Replace or remove it."
        case let .rateLimited(retryAfter): retryAfter.map { "Discord rate limited delivery. Retry after \(Int(ceil($0))) seconds." }
            ?? "Discord rate limited delivery. Try again shortly."
        case .unavailable: "Discord delivery is temporarily unavailable."
        }
    }
}

enum DiscordWebhookValidator {
    static func validate(_ value: String) throws -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme == "https",
              components.host?.lowercased() == "discord.com",
              components.port == nil,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              let url = components.url
        else { throw DiscordWebhookError.invalidURL }
        let parts = components.path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 4,
              parts[0] == "api",
              parts[1] == "webhooks",
              parts[2].allSatisfy(\.isNumber),
              parts[2].count >= 17,
              parts[3].count >= 20
        else { throw DiscordWebhookError.invalidURL }
        return url
    }

    static func redactedDescription(configured: Bool) -> String {
        configured ? "Saved in macOS Keychain - URL hidden" : "Not configured"
    }
}

protocol DiscordWebhookStoring: Sendable {
    func containsWebhook() throws -> Bool
    func webhook() throws -> String?
    func setWebhook(_ value: String) throws
    func removeWebhook() throws
}

struct KeychainDiscordWebhookStore: DiscordWebhookStoring {
    static let service = "com.ziadnasreldin.zoid99.discord"
    static let account = "notification-webhook"

    func containsWebhook() throws -> Bool {
        var query = baseQuery
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = false
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess { return true }
        if status == errSecItemNotFound { return false }
        throw CredentialStoreError.unexpectedStatus(status)
    }

    func webhook() throws -> String? {
        var query = baseQuery
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw CredentialStoreError.unexpectedStatus(status)
        }
        return String(data: data, encoding: .utf8)
    }

    func setWebhook(_ value: String) throws {
        let data = Data(value.utf8)
        let status = SecItemCopyMatching(baseQuery as CFDictionary, nil)
        if status == errSecSuccess {
            let updateStatus = SecItemUpdate(
                baseQuery as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw CredentialStoreError.unexpectedStatus(updateStatus)
            }
            return
        }
        guard status == errSecItemNotFound else { throw CredentialStoreError.unexpectedStatus(status) }
        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw CredentialStoreError.unexpectedStatus(addStatus) }
    }

    func removeWebhook() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.unexpectedStatus(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
    }
}

struct DiscordOpportunityMessage: Equatable, Sendable {
    let content: String

    static func format(_ opportunity: Opportunity) -> DiscordOpportunityMessage {
        let source = opportunity.originalSource ?? opportunity.items.min(by: { $0.publishedAt < $1.publishedAt })
        let reason = concise(opportunity.coverageExplanation, limit: 700)
        var lines = [
            "**Zoid 99 - New research opportunity**",
            concise(opportunity.title, limit: 220),
            "Priority: \(opportunity.isHighPriority ? "High" : "Standard") - Score \(opportunity.score.total)",
            "Source: \(concise(source?.author ?? "Verified research sources", limit: 120))",
            "Reason: \(reason.isEmpty ? "Strong verified signal with timely regional relevance." : reason)",
        ]
        if let url = source?.url,
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           components.scheme?.lowercased() == "https",
           components.host != nil,
           components.user == nil,
           components.password == nil {
            lines.append("Review source: \(url.absoluteString)")
        }
        return DiscordOpportunityMessage(content: lines.joined(separator: "\n"))
    }

    static let test = DiscordOpportunityMessage(
        content: "**Zoid 99 - Discord test**\nSecure local delivery is configured. No research or private activity was included."
    )

    private static func concise(_ value: String, limit: Int) -> String {
        let singleLine = value
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard singleLine.count > limit else { return singleLine }
        return String(singleLine.prefix(limit - 1)) + "…"
    }
}

enum DiscordDeliveryStatus: Equatable, Sendable {
    case notConfigured
    case disabled
    case ready
    case validating
    case delivered(Date)
    case failed(String)

    var label: String {
        switch self {
        case .notConfigured: "Not configured"
        case .disabled: "Disabled"
        case .ready: "Ready"
        case .validating: "Validating"
        case .delivered: "Delivered"
        case let .failed(message): message
        }
    }
}

protocol DiscordNotificationServicing: Sendable {
    func isConfigured() async -> Bool
    func configure(_ value: String) async throws
    func remove() async throws
    func send(_ message: DiscordOpportunityMessage) async throws
}

actor DiscordNotificationService: DiscordNotificationServicing {
    typealias Sleeper = @Sendable (TimeInterval) async throws -> Void

    private let store: any DiscordWebhookStoring
    private let transport: any HTTPTransport
    private let sleeper: Sleeper
    private let maximumAttempts: Int

    init(
        store: any DiscordWebhookStoring = KeychainDiscordWebhookStore(),
        transport: any HTTPTransport = URLSessionHTTPTransport(),
        maximumAttempts: Int = 3,
        sleeper: @escaping Sleeper = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.store = store
        self.transport = transport
        self.maximumAttempts = min(3, max(1, maximumAttempts))
        self.sleeper = sleeper
    }

    func isConfigured() -> Bool {
        (try? store.containsWebhook()) == true
    }

    func configure(_ value: String) async throws {
        let url = try DiscordWebhookValidator.validate(value)
        var request = HTTPRequest(url: url)
        request.method = "GET"
        request.timeout = 10
        let response = try await transport.send(request)
        switch response.statusCode {
        case 200...299:
            try store.setWebhook(url.absoluteString)
        case 401, 403, 404:
            throw DiscordWebhookError.rejected
        case 429:
            throw DiscordWebhookError.rateLimited(retryAfter: retryDelay(response))
        default:
            throw DiscordWebhookError.unavailable
        }
    }

    func remove() throws {
        try store.removeWebhook()
    }

    func send(_ message: DiscordOpportunityMessage) async throws {
        guard let value = try store.webhook() else { throw DiscordWebhookError.notConfigured }
        let url = try DiscordWebhookValidator.validate(value)
        let body = try JSONEncoder().encode(DiscordPayload(content: message.content))
        var request = HTTPRequest(url: url)
        request.method = "POST"
        request.headers = ["Content-Type": "application/json", "User-Agent": "Zoid99/0.2"]
        request.body = body
        request.timeout = 10

        for attempt in 1...maximumAttempts {
            let response: HTTPResponse
            do {
                response = try await transport.send(request)
            } catch {
                if attempt == maximumAttempts { throw DiscordWebhookError.unavailable }
                try await sleeper(min(4, pow(2, Double(attempt - 1)) * 0.5))
                continue
            }
            if (200...299).contains(response.statusCode) { return }
            if response.statusCode == 401 || response.statusCode == 403 || response.statusCode == 404 {
                throw DiscordWebhookError.rejected
            }
            if response.statusCode == 429 {
                let delay = retryDelay(response)
                if attempt == maximumAttempts { throw DiscordWebhookError.rateLimited(retryAfter: delay) }
                try await sleeper(delay ?? min(4, pow(2, Double(attempt - 1)) * 0.5))
                continue
            }
            if (500...599).contains(response.statusCode), attempt < maximumAttempts {
                try await sleeper(min(4, pow(2, Double(attempt - 1)) * 0.5))
                continue
            }
            throw DiscordWebhookError.unavailable
        }
    }

    private func retryDelay(_ response: HTTPResponse) -> TimeInterval? {
        if let raw = response.header("Retry-After"), let value = TimeInterval(raw) {
            return min(30, max(0.25, value))
        }
        if let payload = try? JSONDecoder().decode(DiscordRateLimitPayload.self, from: response.body) {
            return min(30, max(0.25, payload.retryAfter))
        }
        return nil
    }
}

struct DiscordProcessingResult: Sendable, Equatable {
    let deliveredOpportunityIDs: Set<UUID>
    let status: DiscordDeliveryStatus
}

struct DiscordNotificationCoordinator: Sendable {
    let service: any DiscordNotificationServicing

    func process(
        opportunities: [Opportunity],
        enabled: Bool,
        deliveredOpportunityIDs: Set<UUID>,
        now: Date = .now
    ) async -> DiscordProcessingResult {
        guard enabled else {
            return DiscordProcessingResult(
                deliveredOpportunityIDs: deliveredOpportunityIDs,
                status: .disabled
            )
        }
        guard await service.isConfigured() else {
            return DiscordProcessingResult(
                deliveredOpportunityIDs: deliveredOpportunityIDs,
                status: .notConfigured
            )
        }
        let fresh = opportunities.filter {
            $0.dataTruth != .fixture
                && !deliveredOpportunityIDs.contains($0.id)
        }
        guard !fresh.isEmpty else {
            return DiscordProcessingResult(
                deliveredOpportunityIDs: deliveredOpportunityIDs,
                status: .ready
            )
        }

        var delivered = deliveredOpportunityIDs
        for opportunity in fresh {
            do {
                try await service.send(.format(opportunity))
                delivered.insert(opportunity.id)
            } catch {
                let message = (error as? LocalizedError)?.errorDescription
                    ?? "Discord delivery failed safely."
                return DiscordProcessingResult(
                    deliveredOpportunityIDs: delivered,
                    status: .failed(message)
                )
            }
        }
        return DiscordProcessingResult(
            deliveredOpportunityIDs: delivered,
            status: .delivered(now)
        )
    }
}

private struct DiscordPayload: Encodable {
    let content: String
    let allowedMentions = AllowedMentions()

    enum CodingKeys: String, CodingKey {
        case content
        case allowedMentions = "allowed_mentions"
    }

    struct AllowedMentions: Encodable {
        let parse: [String] = []
    }
}

private struct DiscordRateLimitPayload: Decodable {
    let retryAfter: TimeInterval

    enum CodingKeys: String, CodingKey {
        case retryAfter = "retry_after"
    }
}
