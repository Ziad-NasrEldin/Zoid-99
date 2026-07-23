import Foundation

struct InstagramAccessToken: Sendable, CustomStringConvertible {
    fileprivate let value: String

    init(_ value: String) {
        self.value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isEmpty: Bool { value.isEmpty }
    var description: String { "<redacted Instagram access token>" }
}

struct InstagramLocaleEvidence: Equatable, Sendable {
    let language: String
    let country: String
    let evidence: String

    init(language: String, country: String, evidence: String) {
        self.language = language.trimmingCharacters(in: .whitespacesAndNewlines)
        self.country = country.trimmingCharacters(in: .whitespacesAndNewlines)
        self.evidence = evidence.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct InstagramConnectorConfiguration: Sendable {
    let graphAPIVersion: String
    let accessToken: InstagramAccessToken?
    let selectedProfessionalAccountID: String?
    let referenceUsernames: [String]
    let localeEvidenceByUsername: [String: InstagramLocaleEvidence]
    let maximumPagesPerConnection: Int
    let maximumOwnedMediaForCommentRefresh: Int

    init(
        graphAPIVersion: String,
        accessToken: InstagramAccessToken?,
        selectedProfessionalAccountID: String? = nil,
        referenceUsernames: [String] = [],
        localeEvidenceByUsername: [String: InstagramLocaleEvidence] = [:],
        maximumPagesPerConnection: Int = 20,
        maximumOwnedMediaForCommentRefresh: Int = 50
    ) {
        self.graphAPIVersion = graphAPIVersion
            .trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        self.accessToken = accessToken
        self.selectedProfessionalAccountID = selectedProfessionalAccountID
        self.referenceUsernames = Array(
            Set(referenceUsernames.map(Self.normalizedUsername).filter { !$0.isEmpty })
        ).sorted()
        self.localeEvidenceByUsername = Dictionary(
            uniqueKeysWithValues: localeEvidenceByUsername.map {
                (Self.normalizedUsername($0.key), $0.value)
            }
        )
        self.maximumPagesPerConnection = max(1, min(maximumPagesPerConnection, 100))
        self.maximumOwnedMediaForCommentRefresh = max(1, min(maximumOwnedMediaForCommentRefresh, 200))
    }

    var setupIssue: String? {
        if graphAPIVersion.isEmpty {
            return "Set an explicit supported Meta Graph API version."
        }
        if accessToken?.isEmpty != false {
            return "Complete OAuth and store a professional-account access token in secure configuration."
        }
        return nil
    }

    fileprivate static func normalizedUsername(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "@ ").union(.whitespacesAndNewlines))
            .lowercased()
    }
}

struct InstagramIncrementalCursor: Equatable, Sendable {
    var newestMediaTimestamp: Date?
    var newestCommentTimestampByMediaID: [String: Date]
    var ownedMediaIDs: [String]
    var ownedMediaPermalinksByID: [String: URL]

    init(
        newestMediaTimestamp: Date? = nil,
        newestCommentTimestampByMediaID: [String: Date] = [:],
        ownedMediaIDs: [String] = [],
        ownedMediaPermalinksByID: [String: URL] = [:]
    ) {
        self.newestMediaTimestamp = newestMediaTimestamp
        self.newestCommentTimestampByMediaID = newestCommentTimestampByMediaID
        self.ownedMediaIDs = ownedMediaIDs
        self.ownedMediaPermalinksByID = ownedMediaPermalinksByID
    }
}

enum InstagramCollectionState: Equatable, Sendable {
    case available
    case setupRequired(reason: String)
    case unavailable(reason: String, statusCode: Int?)
    case unsupported(reason: String)
    case rateLimited(retryAfter: TimeInterval?)
}

struct InstagramProfessionalAccount: Equatable, Sendable {
    let pageID: String
    let pageName: String
    let instagramAccountID: String
    let username: String?
}

struct InstagramCollection: Sendable {
    let items: [SourceItem]
    let accounts: [InstagramProfessionalAccount]
    let state: InstagramCollectionState
    let cursor: InstagramIncrementalCursor
    let collectedAt: Date
    let evidence: [String]
}

actor InstagramGraphConnector {
    private let configuration: InstagramConnectorConfiguration
    private let transport: any HTTPTransport
    private let graphRoot: URL
    private let timeout: TimeInterval
    private let now: @Sendable () -> Date

    init(
        configuration: InstagramConnectorConfiguration,
        transport: any HTTPTransport = RetryingHTTPTransport(base: URLSessionHTTPTransport()),
        graphRoot: URL = URL(string: "https://graph.facebook.com")!,
        timeout: TimeInterval = 15,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.configuration = configuration
        self.transport = transport
        self.graphRoot = graphRoot
        self.timeout = timeout
        self.now = now
    }

    func collect(after previousCursor: InstagramIncrementalCursor? = nil) async -> InstagramCollection {
        let collectedAt = now()
        let cursor = previousCursor ?? InstagramIncrementalCursor()
        if let issue = configuration.setupIssue {
            return collection(
                state: .setupRequired(reason: issue),
                cursor: cursor,
                collectedAt: collectedAt,
                evidence: [issue]
            )
        }
        guard graphRoot.scheme == "https", graphRoot.host != nil else {
            return collection(
                state: .unsupported(reason: "Instagram Graph API requests require an HTTPS Meta Graph endpoint."),
                cursor: cursor,
                collectedAt: collectedAt,
                evidence: ["No request was made because the configured Graph endpoint is not HTTPS."]
            )
        }

        do {
            let accounts = try await discoverAccounts()
            guard !accounts.isEmpty else {
                return collection(
                    accounts: [],
                    state: .unavailable(
                        reason: "No connected Instagram Business or Creator account was returned for the authorized Facebook Pages.",
                        statusCode: nil
                    ),
                    cursor: cursor,
                    collectedAt: collectedAt,
                    evidence: [
                        "Meta returned no connected professional account. Personal accounts are unsupported."
                    ]
                )
            }
            let selectedAccounts: [InstagramProfessionalAccount]
            if let selectedID = configuration.selectedProfessionalAccountID {
                selectedAccounts = accounts.filter { $0.instagramAccountID == selectedID }
                guard !selectedAccounts.isEmpty else {
                    return collection(
                        accounts: accounts,
                        state: .setupRequired(
                            reason: "The selected Instagram professional account is not available to this token."
                        ),
                        cursor: cursor,
                        collectedAt: collectedAt,
                        evidence: ["Account discovery succeeded, but the configured account ID was not returned."]
                    )
                }
            } else {
                selectedAccounts = accounts
            }

            var output: [SourceItem] = []
            var nextCursor = cursor
            for account in selectedAccounts {
                let media = try await ownedMedia(
                    account: account,
                    collectedAt: collectedAt,
                    newerThan: cursor.newestMediaTimestamp
                )
                output.append(contentsOf: media.items)
                nextCursor.newestMediaTimestamp = maxDate(
                    nextCursor.newestMediaTimestamp,
                    media.allMedia.map(\.timestamp).max()
                )
                nextCursor.ownedMediaIDs = Array(
                    Set((media.allMedia.map(\.id) + cursor.ownedMediaIDs))
                ).sorted()
                for record in media.allMedia {
                    if let permalink = record.permalink {
                        nextCursor.ownedMediaPermalinksByID[record.id] = permalink
                    }
                }

                let commentMediaIDs = Array(
                    nextCursor.ownedMediaIDs.prefix(configuration.maximumOwnedMediaForCommentRefresh)
                )
                for mediaID in commentMediaIDs {
                    guard let mediaPermalink = nextCursor.ownedMediaPermalinksByID[mediaID] else {
                        continue
                    }
                    let comments = try await comments(
                        mediaID: mediaID,
                        mediaPermalink: mediaPermalink,
                        ownerUsername: account.username,
                        collectedAt: collectedAt,
                        newerThan: cursor.newestCommentTimestampByMediaID[mediaID]
                    )
                    output.append(contentsOf: comments.items)
                    nextCursor.newestCommentTimestampByMediaID[mediaID] = maxDate(
                        nextCursor.newestCommentTimestampByMediaID[mediaID],
                        comments.newestTimestamp
                    )
                }
            }

            for username in configuration.referenceUsernames {
                output.append(
                    contentsOf: try await referenceMedia(
                        username: username,
                        requestingAccountID: selectedAccounts[0].instagramAccountID,
                        collectedAt: collectedAt
                    )
                )
            }

            return collection(
                items: deduplicated(output),
                accounts: accounts,
                state: .available,
                cursor: nextCursor,
                collectedAt: collectedAt,
                evidence: [
                    "Collected owned professional-account media and comments through the official Instagram Graph API.",
                    referenceEvidence
                ].filter { !$0.isEmpty }
            )
        } catch let failure as InstagramGraphFailure {
            return collection(
                state: failure.state,
                cursor: cursor,
                collectedAt: collectedAt,
                evidence: [failure.evidence]
            )
        } catch {
            return collection(
                state: .unavailable(reason: "The Instagram Graph API could not be reached.", statusCode: nil),
                cursor: cursor,
                collectedAt: collectedAt,
                evidence: ["The transport failed without exposing credentials: \(error.localizedDescription)"]
            )
        }
    }

    private var referenceEvidence: String {
        guard !configuration.referenceUsernames.isEmpty else { return "" }
        return "Collected only configured professional-account reference data through Meta Business Discovery. This is not arbitrary public Instagram monitoring."
    }

    private func discoverAccounts() async throws -> [InstagramProfessionalAccount] {
        var accounts: [InstagramProfessionalAccount] = []
        try await pages(
            path: "me/accounts",
            query: [
                URLQueryItem(
                    name: "fields",
                    value: "id,name,instagram_business_account{id,username}"
                ),
                URLQueryItem(name: "limit", value: "100")
            ]
        ) { (page: PageEnvelope<FacebookPage>) in
            accounts.append(contentsOf: page.data.compactMap { page in
                guard let instagram = page.instagramBusinessAccount else { return nil }
                return InstagramProfessionalAccount(
                    pageID: page.id,
                    pageName: page.name,
                    instagramAccountID: instagram.id,
                    username: instagram.username
                )
            })
            return true
        }
        return accounts
    }

    private func ownedMedia(
        account: InstagramProfessionalAccount,
        collectedAt: Date,
        newerThan cutoff: Date?
    ) async throws -> (items: [SourceItem], allMedia: [MediaRecord]) {
        var items: [SourceItem] = []
        var allMedia: [MediaRecord] = []
        try await pages(
            path: "\(account.instagramAccountID)/media",
            query: [
                URLQueryItem(name: "fields", value: MediaRecord.fields),
                URLQueryItem(name: "limit", value: "100")
            ]
        ) { (page: PageEnvelope<MediaRecord>) in
            allMedia.append(contentsOf: page.data)
            let fresh = page.data.filter { cutoff == nil || $0.timestamp > cutoff! }
            items.append(contentsOf: fresh.compactMap {
                mapMedia(
                    $0,
                    fallbackUsername: account.username,
                    isOwned: true,
                    collectedAt: collectedAt
                )
            })
            return cutoff == nil || page.data.contains { $0.timestamp > cutoff! }
        }
        return (items, allMedia)
    }

    private func comments(
        mediaID: String,
        mediaPermalink: URL,
        ownerUsername: String?,
        collectedAt: Date,
        newerThan cutoff: Date?
    ) async throws -> (items: [SourceItem], newestTimestamp: Date?) {
        var records: [CommentRecord] = []
        try await pages(
            path: "\(mediaID)/comments",
            query: [
                URLQueryItem(name: "fields", value: "id,text,timestamp,username,from,parent_id,like_count"),
                URLQueryItem(name: "limit", value: "100")
            ]
        ) { (page: PageEnvelope<CommentRecord>) in
            let fresh = page.data.filter { cutoff == nil || $0.timestamp > cutoff! }
            records.append(contentsOf: fresh)
            return cutoff == nil || page.data.contains { $0.timestamp > cutoff! }
        }
        return (
            records.compactMap {
                mapComment(
                    $0,
                    mediaID: mediaID,
                    mediaPermalink: mediaPermalink,
                    ownerUsername: ownerUsername,
                    collectedAt: collectedAt
                )
            },
            records.map(\.timestamp).max()
        )
    }

    private func referenceMedia(
        username: String,
        requestingAccountID: String,
        collectedAt: Date
    ) async throws -> [SourceItem] {
        let encodedUsername = username.replacingOccurrences(of: "\"", with: "")
        let fields = "business_discovery.username(\(encodedUsername)){id,username,media.limit(100){\(MediaRecord.fields)}}"
        let response: BusinessDiscoveryEnvelope = try await request(
            path: requestingAccountID,
            query: [URLQueryItem(name: "fields", value: fields)]
        )
        guard let discovery = response.businessDiscovery else { return [] }
        return discovery.media?.data.compactMap {
            mapMedia($0, fallbackUsername: discovery.username, isOwned: false, collectedAt: collectedAt)
        } ?? []
    }

    private func pages<T: Decodable>(
        path: String,
        query: [URLQueryItem],
        consume: (PageEnvelope<T>) throws -> Bool
    ) async throws {
        var after: String?
        var seenCursors = Set<String>()
        for _ in 0..<configuration.maximumPagesPerConnection {
            var pageQuery = query
            if let after { pageQuery.append(URLQueryItem(name: "after", value: after)) }
            let page: PageEnvelope<T> = try await request(path: path, query: pageQuery)
            guard try consume(page) else { return }
            guard let next = page.paging?.cursors?.after, page.paging?.next != nil else { return }
            guard seenCursors.insert(next).inserted else {
                throw InstagramGraphFailure(
                    state: .unavailable(reason: "Meta returned a repeated pagination cursor.", statusCode: nil),
                    evidence: "Pagination stopped safely before repeating a page."
                )
            }
            after = next
        }
        throw InstagramGraphFailure(
            state: .unavailable(reason: "The configured Instagram pagination safety limit was reached.", statusCode: nil),
            evidence: "Collection stopped after \(configuration.maximumPagesPerConnection) pages."
        )
    }

    private func request<T: Decodable>(path: String, query: [URLQueryItem]) async throws -> T {
        let url = try endpoint(path: path, query: query)
        guard let token = configuration.accessToken else {
            throw InstagramGraphFailure(
                state: .setupRequired(reason: "Instagram OAuth is incomplete."),
                evidence: "No request was made."
            )
        }
        let response = try await transport.send(
            HTTPRequest(
                url: url,
                headers: [
                    "Accept": "application/json",
                    "Authorization": "Bearer \(token.value)",
                    "User-Agent": "Zoid99/1.0"
                ],
                timeout: timeout
            )
        )
        if let retryAfter = rateLimit(response) {
            throw InstagramGraphFailure(
                state: .rateLimited(retryAfter: retryAfter),
                evidence: "Meta returned a rate-limit signal. Collection stopped without retrying the limited request."
            )
        }
        guard (200...299).contains(response.statusCode) else {
            let graphError = try? JSONDecoder.instagram.decode(GraphErrorEnvelope.self, from: response.body)
            let reason = graphError?.error.message ?? "Meta returned HTTP \(response.statusCode)."
            throw InstagramGraphFailure(
                state: .unavailable(reason: sanitized(reason), statusCode: response.statusCode),
                evidence: "The official Instagram Graph API rejected the request."
            )
        }
        do {
            return try JSONDecoder.instagram.decode(T.self, from: response.body)
        } catch {
            throw InstagramGraphFailure(
                state: .unavailable(reason: "Meta returned an unexpected response shape.", statusCode: response.statusCode),
                evidence: "No SourceItem was invented from the malformed response."
            )
        }
    }

    private func endpoint(path: String, query: [URLQueryItem]) throws -> URL {
        let base = graphRoot
            .appending(path: configuration.graphAPIVersion)
            .appending(path: path)
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        components.queryItems = query
        guard let url = components.url else { throw URLError(.badURL) }
        return url
    }

    private func rateLimit(_ response: HTTPResponse) -> TimeInterval?? {
        if response.statusCode == 429 {
            return retryAfter(response)
        }
        if let graphError = try? JSONDecoder.instagram.decode(GraphErrorEnvelope.self, from: response.body),
           [4, 17, 32, 613].contains(graphError.error.code) {
            return retryAfter(response)
        }
        for header in ["X-App-Usage", "X-Page-Usage", "X-Business-Use-Case-Usage"] {
            guard let value = response.header(header),
                  let data = value.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else { continue }
            if usageReachedLimit(object) { return retryAfter(response) }
        }
        return nil
    }

    private func retryAfter(_ response: HTTPResponse) -> TimeInterval? {
        guard let value = response.header("Retry-After") else { return nil }
        return TimeInterval(value)
    }

    private func usageReachedLimit(_ value: Any) -> Bool {
        if let dictionary = value as? [String: Any] {
            for key in ["call_count", "total_cputime", "total_time"] {
                if let number = dictionary[key] as? NSNumber, number.doubleValue >= 100 {
                    return true
                }
            }
            return dictionary.values.contains {
                $0 is [String: Any] || $0 is [Any] ? usageReachedLimit($0) : false
            }
        }
        if let array = value as? [Any] {
            return array.contains(where: usageReachedLimit)
        }
        return false
    }

    private func mapMedia(
        _ media: MediaRecord,
        fallbackUsername: String?,
        isOwned: Bool,
        collectedAt: Date
    ) -> SourceItem? {
        guard let permalink = media.permalink,
              permalink.scheme == "https",
              !media.id.isEmpty else { return nil }
        let username = media.username ?? fallbackUsername ?? "Unknown Instagram professional account"
        let locale = locale(for: username)
        let kind = media.mediaProductType ?? media.mediaType ?? "Media"
        let caption = media.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = caption.isEmpty ? "Instagram \(kind)" : firstLine(caption)
        return SourceItem(
            id: stableID(scope: isOwned ? "instagram-owned-media" : "instagram-reference-media", externalID: media.id),
            group: .instagram,
            externalID: media.id,
            title: title,
            summary: mediaSummary(media, caption: caption),
            author: username,
            url: permalink,
            publishedAt: media.timestamp,
            collectedAt: collectedAt,
            language: locale.language,
            country: locale.country,
            topicKey: "unclustered-\(stableID(scope: "instagram-media", externalID: media.id).uuidString.lowercased())",
            isOriginalSource: isOwned,
            credibility: isOwned ? 0.9 : 0.7,
            engagement: max(0, (media.likeCount ?? 0) + (media.commentsCount ?? 0)),
            verification: isOwned ? .confirmed : .unverified,
            dataTruth: .live
        )
    }

    private func mapComment(
        _ comment: CommentRecord,
        mediaID: String,
        mediaPermalink: URL,
        ownerUsername: String?,
        collectedAt: Date
    ) -> SourceItem? {
        let text = comment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let username = comment.username ?? comment.from?.username ?? "Unknown Instagram commenter"
        let locale = locale(for: username)
        return SourceItem(
            id: stableID(scope: "instagram-comment", externalID: comment.id),
            group: .comments,
            externalID: comment.id,
            title: firstLine(text),
            summary: text,
            author: username,
            url: mediaPermalink,
            publishedAt: comment.timestamp,
            collectedAt: collectedAt,
            language: locale.language,
            country: locale.country,
            topicKey: "instagram-comments-\(mediaID)",
            isOriginalSource: false,
            credibility: username.caseInsensitiveCompare(ownerUsername ?? "") == .orderedSame ? 0.8 : 0.5,
            engagement: max(0, comment.likeCount ?? 0),
            verification: .unverified,
            dataTruth: .live
        )
    }

    private func locale(for username: String) -> (language: String, country: String) {
        let key = InstagramConnectorConfiguration.normalizedUsername(username)
        guard let evidence = configuration.localeEvidenceByUsername[key],
              !evidence.evidence.isEmpty else {
            return ("und", "Unknown")
        }
        return (
            evidence.language.isEmpty ? "und" : evidence.language,
            evidence.country.isEmpty ? "Unknown" : evidence.country
        )
    }

    private func mediaSummary(_ media: MediaRecord, caption: String) -> String {
        let metadata = [
            media.mediaProductType.map { "product=\($0)" },
            media.mediaType.map { "type=\($0)" },
            media.duration.map { "duration=\($0)s" },
            media.thumbnailURL == nil ? nil : "thumbnail=available",
            media.children?.data.isEmpty == false ? "children=\(media.children?.data.count ?? 0)" : nil
        ].compactMap { $0 }.joined(separator: ", ")
        if caption.isEmpty { return metadata }
        return metadata.isEmpty ? caption : "\(caption)\n\(metadata)"
    }

    private func firstLine(_ value: String) -> String {
        let line = value.components(separatedBy: .newlines).first ?? value
        return String(line.prefix(140))
    }

    private func stableID(scope: String, externalID: String) -> UUID {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in "\(scope):\(externalID)".utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        let hex = String(format: "%016llx", hash)
        return UUID(uuidString: "00000000-0000-0000-\(hex.prefix(4))-\(hex.suffix(12))")!
    }

    private func deduplicated(_ items: [SourceItem]) -> [SourceItem] {
        Array(Dictionary(items.map { ("\($0.group.rawValue):\($0.externalID)", $0) }) { first, _ in first }.values)
            .sorted { $0.publishedAt > $1.publishedAt }
    }

    private func maxDate(_ left: Date?, _ right: Date?) -> Date? {
        [left, right].compactMap { $0 }.max()
    }

    private func sanitized(_ value: String) -> String {
        guard let token = configuration.accessToken?.value, !token.isEmpty else { return value }
        return value.replacingOccurrences(of: token, with: "<redacted>")
    }

    private func collection(
        items: [SourceItem] = [],
        accounts: [InstagramProfessionalAccount] = [],
        state: InstagramCollectionState,
        cursor: InstagramIncrementalCursor,
        collectedAt: Date,
        evidence: [String]
    ) -> InstagramCollection {
        InstagramCollection(
            items: items,
            accounts: accounts,
            state: state,
            cursor: cursor,
            collectedAt: collectedAt,
            evidence: evidence
        )
    }
}

private struct InstagramGraphFailure: Error {
    let state: InstagramCollectionState
    let evidence: String
}

private struct PageEnvelope<Value: Decodable>: Decodable {
    let data: [Value]
    let paging: Paging?
}

private struct Paging: Decodable {
    struct Cursors: Decodable {
        let after: String?
    }

    let cursors: Cursors?
    let next: URL?
}

private struct FacebookPage: Decodable {
    struct InstagramAccount: Decodable {
        let id: String
        let username: String?
    }

    let id: String
    let name: String
    let instagramBusinessAccount: InstagramAccount?

    enum CodingKeys: String, CodingKey {
        case id, name
        case instagramBusinessAccount = "instagram_business_account"
    }
}

private struct MediaRecord: Decodable {
    struct Children: Decodable {
        let data: [Child]
    }

    struct Child: Decodable {
        let id: String
        let mediaType: String?
        let mediaURL: URL?

        enum CodingKeys: String, CodingKey {
            case id
            case mediaType = "media_type"
            case mediaURL = "media_url"
        }
    }

    static let fields = [
        "id", "caption", "media_type", "media_product_type", "media_url", "permalink",
        "thumbnail_url", "timestamp", "username", "like_count", "comments_count",
        "duration", "children{id,media_type,media_url}"
    ].joined(separator: ",")

    let id: String
    let caption: String?
    let mediaType: String?
    let mediaProductType: String?
    let mediaURL: URL?
    let permalink: URL?
    let thumbnailURL: URL?
    let timestamp: Date
    let username: String?
    let likeCount: Int?
    let commentsCount: Int?
    let duration: Double?
    let children: Children?

    enum CodingKeys: String, CodingKey {
        case id, caption, permalink, timestamp, username, children
        case mediaType = "media_type"
        case mediaProductType = "media_product_type"
        case mediaURL = "media_url"
        case thumbnailURL = "thumbnail_url"
        case likeCount = "like_count"
        case commentsCount = "comments_count"
        case duration
    }
}

private struct CommentRecord: Decodable {
    struct Author: Decodable {
        let username: String?
    }

    let id: String
    let text: String
    let timestamp: Date
    let username: String?
    let from: Author?
    let parentID: String?
    let likeCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, text, timestamp, username, from
        case parentID = "parent_id"
        case likeCount = "like_count"
    }
}

private struct BusinessDiscoveryEnvelope: Decodable {
    struct Discovery: Decodable {
        let id: String
        let username: String
        let media: PageEnvelope<MediaRecord>?
    }

    let businessDiscovery: Discovery?

    enum CodingKeys: String, CodingKey {
        case businessDiscovery = "business_discovery"
    }
}

private struct GraphErrorEnvelope: Decodable {
    struct GraphError: Decodable {
        let message: String
        let code: Int
    }

    let error: GraphError
}

private extension JSONDecoder {
    static var instagram: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
