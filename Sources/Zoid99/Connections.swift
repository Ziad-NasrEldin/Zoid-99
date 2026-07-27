import Foundation
import Security

enum ExternalProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case youtube = "YouTube"
    case googleTrends = "Google Trends"
    case meta = "Instagram / Meta"
    case x = "X"
    case officialFeeds = "Official feeds"
    case aiProvider = "AI provider"

    var id: String { rawValue }

    var sourceGroup: SourceGroup? {
        switch self {
        case .youtube: .youtube
        case .googleTrends: .googleTrends
        case .meta: .instagram
        case .x: .x
        case .officialFeeds: .official
        case .aiProvider: nil
        }
    }
}

enum ProviderConnectionState: String, CaseIterable, Codable, Sendable {
    case setupRequired = "Setup required"
    case connected = "Connected"
    case disconnected = "Disconnected"
    case unavailable = "Unavailable"
    case delayed = "Delayed"
    case rateLimited = "Rate limited"
    case cached = "Cached"
    case unsupported = "Unsupported"
    case validating = "Validating"

    var needsAttention: Bool {
        self != .connected && self != .cached && self != .validating
    }
}

enum CredentialBoundary: String, Codable, Sendable {
    case keychain = "macOS Keychain"
    case serverSecret = "Monitoring server secret"
    case none = "No credential required"
}

struct ProviderDefinition: Identifiable, Hashable, Sendable {
    let provider: ExternalProvider
    let prerequisite: String
    let permissionScope: String
    let credentialBoundary: CredentialBoundary
    let setupGuidance: String

    var id: ExternalProvider { provider }

    static let catalog: [ProviderDefinition] = [
        ProviderDefinition(
            provider: .youtube,
            prerequisite: "A YouTube Data API v3 key from a Google Cloud project.",
            permissionScope: "Read public channel data, videos, and comments. Zoid 99 cannot publish or reply.",
            credentialBoundary: .keychain,
            setupGuidance: "Paste a YouTube Data API key. It is validated once and stays in macOS Keychain."
        ),
        ProviderDefinition(
            provider: .googleTrends,
            prerequisite: "Approved access to the official Google Trends API.",
            permissionScope: "Read trend-series data for configured topics and regions.",
            credentialBoundary: .serverSecret,
            setupGuidance: "Configure approved API access on the monitoring server. Alpha access is not assumed."
        ),
        ProviderDefinition(
            provider: .meta,
            prerequisite: "A supported Instagram professional account connected to a Facebook Page.",
            permissionScope: "Read permitted Instagram media and comments. Zoid 99 cannot publish or reply.",
            credentialBoundary: .keychain,
            setupGuidance: "Use Meta OAuth. The long-lived user token stays in macOS Keychain."
        ),
        ProviderDefinition(
            provider: .x,
            prerequisite: "An X developer project with read access.",
            permissionScope: "Read configured accounts, posts, and keyword search results.",
            credentialBoundary: .keychain,
            setupGuidance: "Use an official X API bearer token. It stays in macOS Keychain."
        ),
        ProviderDefinition(
            provider: .officialFeeds,
            prerequisite: "A supported HTTPS RSS, Atom, or GitHub Releases endpoint.",
            permissionScope: "Read public published entries only.",
            credentialBoundary: .none,
            setupGuidance: "No account is needed. Each endpoint is validated before it is marked connected."
        ),
        ProviderDefinition(
            provider: .aiProvider,
            prerequisite: "A supported structured-output model and a server-side API key.",
            permissionScope: "Interpret collected evidence for clustering, summaries, language, and regional relevance.",
            credentialBoundary: .serverSecret,
            setupGuidance: "Configure the API key on the monitoring server. AI output is interpretation, never source evidence."
        )
    ]
}

struct ProviderConnection: Identifiable, Hashable, Sendable {
    var id: ExternalProvider { provider }
    let provider: ExternalProvider
    var state: ProviderConnectionState
    var lastActivity: Date?
    var evidence: String
    var repairAction: String
    var retryAt: Date?
}

struct ProviderValidationResult: Equatable, Sendable {
    let state: ProviderConnectionState
    let evidence: String
    let checkedAt: Date
    let retryAt: Date?
}

protocol ProviderConnectionServicing: Sendable {
    func validate(_ provider: ExternalProvider) async -> ProviderValidationResult
    func connect(_ provider: ExternalProvider, credential: String?) async -> ProviderValidationResult
    func disconnect(_ provider: ExternalProvider) async -> ProviderValidationResult
}

protocol CredentialStoring: Sendable {
    func contains(provider: ExternalProvider) throws -> Bool
    func credential(provider: ExternalProvider) throws -> String?
    func set(_ credential: String, provider: ExternalProvider) throws
    func remove(provider: ExternalProvider) throws
}

enum CredentialStoreError: LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .unexpectedStatus(status):
            "Keychain operation failed with status \(status)."
        }
    }
}

struct KeychainCredentialStore: CredentialStoring {
    private let service = "com.zoid99.external-provider"

    func contains(provider: ExternalProvider) throws -> Bool {
        var query = baseQuery(provider)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = false
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess { return true }
        if status == errSecItemNotFound { return false }
        throw CredentialStoreError.unexpectedStatus(status)
    }

    func credential(provider: ExternalProvider) throws -> String? {
        var query = baseQuery(provider)
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

    func set(_ credential: String, provider: ExternalProvider) throws {
        let data = Data(credential.utf8)
        var query = baseQuery(provider)
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let update = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else { throw CredentialStoreError.unexpectedStatus(updateStatus) }
            return
        }
        guard status == errSecItemNotFound else { throw CredentialStoreError.unexpectedStatus(status) }
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw CredentialStoreError.unexpectedStatus(addStatus) }
    }

    func remove(provider: ExternalProvider) throws {
        let status = SecItemDelete(baseQuery(provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(_ provider: ExternalProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]
    }
}

protocol ProviderCredentialValidating: Sendable {
    func validate(_ provider: ExternalProvider, credential: String?) async -> ProviderValidationResult
}

struct SetupRequiredProviderValidator: ProviderCredentialValidating {
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    func validate(_ provider: ExternalProvider, credential: String?) async -> ProviderValidationResult {
        return ProviderValidationResult(
            state: .unavailable,
            evidence: "A connector-specific validator is required. Access was not marked connected and no credential was stored.",
            checkedAt: now(),
            retryAt: nil
        )
    }
}

struct OfficialProviderCredentialValidator: ProviderCredentialValidating {
    private let transport: any HTTPTransport
    private let now: @Sendable () -> Date

    init(
        transport: any HTTPTransport = RetryingHTTPTransport(base: URLSessionHTTPTransport()),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.transport = transport
        self.now = now
    }

    func validate(_ provider: ExternalProvider, credential: String?) async -> ProviderValidationResult {
        switch provider {
        case .youtube:
            return await validateYouTube(credential)
        case .meta:
            return await validateInstagram(credential)
        case .x:
            return await validateX(credential)
        case .officialFeeds:
            return await validateOfficialFeeds()
        case .googleTrends:
            return result(
                .unsupported,
                "Official Google Trends API access is approval-gated and is not enabled in this local build."
            )
        case .aiProvider:
            return result(.setupRequired, "Configure and validate the AI provider on the monitoring server.")
        }
    }

    private func validateYouTube(_ credential: String?) async -> ProviderValidationResult {
        guard let credential = credential?.trimmedNonEmpty else {
            return result(.setupRequired, "A YouTube Data API key is required. Nothing was stored.")
        }
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/videos")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "id"),
            URLQueryItem(name: "chart", value: "mostPopular"),
            URLQueryItem(name: "maxResults", value: "1"),
            URLQueryItem(name: "regionCode", value: "US"),
            URLQueryItem(name: "key", value: credential),
        ]
        return await validateRequest(
            HTTPRequest(url: components.url!),
            successEvidence: "YouTube Data API read access was validated. The API key is stored only in macOS Keychain.",
            invalidEvidence: "YouTube rejected the API key or the Data API is not enabled for its project."
        )
    }

    private func validateInstagram(_ credential: String?) async -> ProviderValidationResult {
        guard let credential = credential?.trimmedNonEmpty else {
            return result(.setupRequired, "A long-lived Instagram professional-account token is required. Nothing was stored.")
        }
        var components = URLComponents(string: "https://graph.facebook.com/v23.0/me/accounts")!
        components.queryItems = [
            URLQueryItem(name: "fields", value: "id,instagram_business_account"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        return await validateRequest(
            HTTPRequest(
                url: components.url!,
                headers: ["Authorization": "Bearer \(credential)"]
            ),
            successEvidence: "Instagram Graph API read access was validated. The token is stored only in macOS Keychain.",
            invalidEvidence: "Meta rejected the token or it cannot read a connected professional account.",
            isValidSuccessBody: { data in
                guard let envelope = try? JSONDecoder().decode(InstagramValidationEnvelope.self, from: data) else {
                    return false
                }
                return envelope.data.contains { $0.instagramBusinessAccount != nil }
            }
        )
    }

    private func validateX(_ credential: String?) async -> ProviderValidationResult {
        guard let credential = credential?.trimmedNonEmpty else {
            return result(.setupRequired, "An X API read bearer token is required. Nothing was stored.")
        }
        return await validateRequest(
            HTTPRequest(
                url: URL(string: "https://api.x.com/2/users/by/username/XDevelopers?user.fields=id")!,
                headers: ["Authorization": "Bearer \(credential)"]
            ),
            successEvidence: "X API read access was validated. The bearer token is stored only in macOS Keychain.",
            invalidEvidence: "X rejected the bearer token or the project does not have the required read access."
        )
    }

    private func validateOfficialFeeds() async -> ProviderValidationResult {
        let collections = await withTaskGroup(of: ConnectorCollection.self) { group in
            for source in OfficialAISourceCatalog.starter {
                group.addTask { await PublicFeedConnector(source: source).collect() }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        let available = collections.filter { $0.state == .available || $0.state == .delayed }
        guard !available.isEmpty else {
            return result(.unavailable, "No credential-free official source returned published items.")
        }
        let itemCount = available.flatMap(\.items).count
        let state: ProviderConnectionState = available.count == collections.count ? .connected : .delayed
        return result(
            state,
            "\(available.count) of \(collections.count) credential-free official sources returned \(itemCount) published items."
        )
    }

    private func validateRequest(
        _ request: HTTPRequest,
        successEvidence: String,
        invalidEvidence: String,
        isValidSuccessBody: @escaping @Sendable (Data) -> Bool = { _ in true }
    ) async -> ProviderValidationResult {
        do {
            let response = try await transport.send(request)
            if (200...299).contains(response.statusCode) {
                return isValidSuccessBody(response.body)
                    ? result(.connected, successEvidence)
                    : result(.setupRequired, invalidEvidence)
            }
            if response.statusCode == 429 {
                return result(.rateLimited, "The provider rate-limited validation. No credential was stored.")
            }
            if response.statusCode == 401 || response.statusCode == 403 || response.statusCode == 400 {
                return result(.setupRequired, invalidEvidence)
            }
            return result(.unavailable, "The provider returned HTTP \(response.statusCode). No credential was stored.")
        } catch {
            return result(.unavailable, "The provider could not be reached. No credential was stored or displayed.")
        }
    }

    private func result(_ state: ProviderConnectionState, _ evidence: String) -> ProviderValidationResult {
        ProviderValidationResult(state: state, evidence: evidence, checkedAt: now(), retryAt: nil)
    }
}

actor LocalProviderConnectionService: ProviderConnectionServicing {
    private let credentials: any CredentialStoring
    private let validator: any ProviderCredentialValidating
    private let now: @Sendable () -> Date

    init(
        credentials: any CredentialStoring = KeychainCredentialStore(),
        validator: any ProviderCredentialValidating = OfficialProviderCredentialValidator(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.credentials = credentials
        self.validator = validator
        self.now = now
    }

    func validate(_ provider: ExternalProvider) async -> ProviderValidationResult {
        let checkedAt = now()
        guard let definition = ProviderDefinition.catalog.first(where: { $0.provider == provider }) else {
            return ProviderValidationResult(
                state: .unsupported,
                evidence: "This provider is not supported by this build.",
                checkedAt: checkedAt,
                retryAt: nil
            )
        }
        switch definition.credentialBoundary {
        case .none:
            return await validator.validate(provider, credential: nil)
        case .serverSecret:
            return ProviderValidationResult(
                state: .setupRequired,
                evidence: "Validation must run on the monitoring server. No server credential is accepted or stored by this app.",
                checkedAt: checkedAt,
                retryAt: nil
            )
        case .keychain:
            do {
                guard let credential = try credentials.credential(provider: provider) else {
                    return ProviderValidationResult(
                        state: .setupRequired,
                        evidence: "No credential is stored in macOS Keychain.",
                        checkedAt: checkedAt,
                        retryAt: nil
                    )
                }
                return await validator.validate(provider, credential: credential)
            } catch {
                return ProviderValidationResult(
                    state: .unavailable,
                    evidence: "Keychain access is unavailable. No credential was displayed or logged.",
                    checkedAt: checkedAt,
                    retryAt: nil
                )
            }
        }
    }

    func connect(_ provider: ExternalProvider, credential: String?) async -> ProviderValidationResult {
        let checkedAt = now()
        guard let definition = ProviderDefinition.catalog.first(where: { $0.provider == provider }) else {
            return ProviderValidationResult(state: .unsupported, evidence: "This provider is unsupported.", checkedAt: checkedAt, retryAt: nil)
        }
        switch definition.credentialBoundary {
        case .none:
            return await validator.validate(provider, credential: nil)
        case .serverSecret:
            return ProviderValidationResult(
                state: .setupRequired,
                evidence: "Configure and validate this credential on the monitoring server.",
                checkedAt: checkedAt,
                retryAt: nil
            )
        case .keychain:
            let trimmed = credential?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else {
                return ProviderValidationResult(
                    state: .setupRequired,
                    evidence: "A credential is required. Nothing was stored.",
                    checkedAt: checkedAt,
                    retryAt: nil
                )
            }
            let validation = await validator.validate(provider, credential: trimmed)
            guard validation.state == .connected else { return validation }
            do {
                try credentials.set(trimmed, provider: provider)
                return validation
            } catch {
                return ProviderValidationResult(
                    state: .unavailable,
                    evidence: "The credential could not be stored in macOS Keychain.",
                    checkedAt: checkedAt,
                    retryAt: nil
                )
            }
        }
    }

    func disconnect(_ provider: ExternalProvider) async -> ProviderValidationResult {
        let checkedAt = now()
        do {
            try credentials.remove(provider: provider)
            return ProviderValidationResult(
                state: .disconnected,
                evidence: "Local authorization was removed. Previously collected evidence remains available.",
                checkedAt: checkedAt,
                retryAt: nil
            )
        } catch {
            return ProviderValidationResult(
                state: .unavailable,
                evidence: "Local authorization could not be removed. No credential was displayed or logged.",
                checkedAt: checkedAt,
                retryAt: nil
            )
        }
    }
}

private struct InstagramValidationEnvelope: Decodable {
    struct Page: Decodable {
        struct ProfessionalAccount: Decodable {
            let id: String
        }

        let instagramBusinessAccount: ProfessionalAccount?

        enum CodingKeys: String, CodingKey {
            case instagramBusinessAccount = "instagram_business_account"
        }
    }

    let data: [Page]
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
