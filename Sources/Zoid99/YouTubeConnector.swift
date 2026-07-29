import Foundation

enum YouTubeCredential: Equatable, Sendable {
    case apiKey(String)
    case oauthAccessToken(String)
}

protocol YouTubeCredentialProviding: Sendable {
    func credential() async -> YouTubeCredential?
}

struct StaticYouTubeCredentialProvider: YouTubeCredentialProviding {
    let value: YouTubeCredential?

    init(_ value: YouTubeCredential?) {
        self.value = value
    }

    func credential() async -> YouTubeCredential? {
        value
    }
}

struct UserDefaultsYouTubeCredentialProvider: YouTubeCredentialProviding {
    static let prefix = "com.zoid99.youtube-data-api"

    let account: String
    let kind: CredentialKind

    enum CredentialKind: String, Sendable {
        case apiKey = "api-key"
        case oauthAccessToken = "oauth-access-token"
    }

    func credential() async -> YouTubeCredential? {
        let key = "\(Self.prefix).\(account).\(kind.rawValue)"
        guard let value = UserDefaults.standard.string(forKey: key), !value.isEmpty else {
            return nil
        }
        switch kind {
        case .apiKey:
            return .apiKey(value)
        case .oauthAccessToken:
            return .oauthAccessToken(value)
        }
    }
}

enum YouTubeChannelKind: String, Codable, Sendable {
    case owned
    case reference
}

struct YouTubeMonitoredChannel: Codable, Equatable, Sendable {
    let id: String?
    let kind: YouTubeChannelKind
    let language: String
    let country: String

    static func owned(language: String, country: String) -> Self {
        .init(id: nil, kind: .owned, language: language, country: country)
    }

    static func reference(id: String, language: String, country: String) -> Self {
        .init(id: id, kind: .reference, language: language, country: country)
    }
}

struct YouTubeVideoTarget: Codable, Equatable, Sendable {
    let id: String
    let channelKind: YouTubeChannelKind
    let channelTitle: String
    let language: String
    let country: String
}

struct YouTubeSearchTarget: Codable, Equatable, Sendable {
    let query: String
    let language: String
    let country: String
    let publishedAfter: Date?

    init(query: String, language: String, country: String, publishedAfter: Date? = nil) {
        self.query = query
        self.language = language
        self.country = country
        self.publishedAfter = publishedAfter
    }
}

struct YouTubeCollectionLimits: Equatable, Sendable {
    let maxPagesPerRequest: Int
    let maxItemsPerPage: Int
    let maxQuotaUnitsPerRun: Int

    init(maxPagesPerRequest: Int = 2, maxItemsPerPage: Int = 25, maxQuotaUnitsPerRun: Int = 20) {
        self.maxPagesPerRequest = min(max(1, maxPagesPerRequest), 4)
        self.maxItemsPerPage = min(max(1, maxItemsPerPage), 50)
        self.maxQuotaUnitsPerRun = min(max(1, maxQuotaUnitsPerRun), 100)
    }
}

enum YouTubeCollectionState: Equatable, Sendable {
    case available
    case setupRequired
    case rateLimited(retryAfter: TimeInterval?)
    case unavailable(statusCode: Int?)
}

struct YouTubeCollection: Sendable {
    let items: [SourceItem]
    let state: YouTubeCollectionState
    let collectedAt: Date
    let quotaUnitsUsed: Int
    let evidence: String
}

struct YouTubeDataConnector: Sendable {
    private static let baseURL = URL(string: "https://www.googleapis.com/youtube/v3")!

    let credentialProvider: any YouTubeCredentialProviding
    let transport: any HTTPTransport
    let limits: YouTubeCollectionLimits
    let now: @Sendable () -> Date

    init(
        credentialProvider: any YouTubeCredentialProviding,
        transport: any HTTPTransport = RetryingHTTPTransport(base: URLSessionHTTPTransport()),
        limits: YouTubeCollectionLimits = .init(),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.credentialProvider = credentialProvider
        self.transport = transport
        self.limits = limits
        self.now = now
    }

    func collectRecentVideos(channel: YouTubeMonitoredChannel) async -> YouTubeCollection {
        let collectedAt = now()
        guard let credential = await credentialProvider.credential() else {
            return setupRequired(at: collectedAt)
        }
        if channel.kind == .owned, !credential.isOAuth {
            return YouTubeCollection(
                items: [],
                state: .setupRequired,
                collectedAt: collectedAt,
                quotaUnitsUsed: 0,
                evidence: "OAuth authorization is required for the owned YouTube channel."
            )
        }

        var quotaUsed = 0
        let channelParameters: [URLQueryItem]
        if channel.kind == .owned {
            channelParameters = [.init(name: "mine", value: "true")]
        } else if let id = channel.id, !id.isEmpty {
            channelParameters = [.init(name: "id", value: id)]
        } else {
            return YouTubeCollection(
                items: [],
                state: .setupRequired,
                collectedAt: collectedAt,
                quotaUnitsUsed: 0,
                evidence: "A YouTube channel ID is required for a reference channel."
            )
        }

        let channelResult = await request(
            path: "channels",
            query: [.init(name: "part", value: "snippet,contentDetails")] + channelParameters,
            credential: credential
        )
        quotaUsed += 1
        switch channelResult {
        case let .failure(state, evidence):
            return .init(
                items: [],
                state: state,
                collectedAt: collectedAt,
                quotaUnitsUsed: quotaUsed,
                evidence: evidence
            )
        case let .success(data, _):
            guard let channelPage = try? JSONDecoder.youtube.decode(YouTubeChannelPage.self, from: data),
                  let resolved = channelPage.items.first,
                  !resolved.contentDetails.relatedPlaylists.uploads.isEmpty else {
                return unavailable(at: collectedAt, quotaUsed: quotaUsed, evidence: "YouTube returned no matching channel.")
            }
            return await collectUploadPlaylist(
                id: resolved.contentDetails.relatedPlaylists.uploads,
                channel: channel,
                channelTitle: resolved.snippet.title,
                credential: credential,
                collectedAt: collectedAt,
                initialQuotaUsed: quotaUsed
            )
        }
    }

    func search(_ target: YouTubeSearchTarget) async -> YouTubeCollection {
        let collectedAt = now()
        guard let credential = await credentialProvider.credential() else {
            return setupRequired(at: collectedAt)
        }
        let query = target.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return .init(
                items: [],
                state: .setupRequired,
                collectedAt: collectedAt,
                quotaUnitsUsed: 0,
                evidence: "A YouTube search query is required."
            )
        }
        let baseParameters = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "type", value: "video"),
            URLQueryItem(name: "order", value: "date"),
            URLQueryItem(name: "maxResults", value: String(limits.maxItemsPerPage)),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "relevanceLanguage", value: target.language),
            URLQueryItem(name: "regionCode", value: target.country.uppercased())
        ]
        var items: [SourceItem] = []
        var pageToken: String?
        var quotaUsed = 0
        searchPages: for _ in 0..<limits.maxPagesPerRequest {
            guard quotaUsed < limits.maxQuotaUnitsPerRun else {
                return quotaBudgetResult(items: items, collectedAt: collectedAt, quotaUsed: quotaUsed)
            }
            var parameters = baseParameters
            if let publishedAfter = target.publishedAfter {
                parameters.append(.init(name: "publishedAfter", value: publishedAfter.ISO8601Format()))
            }
            if let pageToken {
                parameters.append(.init(name: "pageToken", value: pageToken))
            }
            let response = await request(path: "search", query: parameters, credential: credential)
            quotaUsed += 1
            switch response {
            case let .failure(state, evidence):
                return .init(items: items, state: state, collectedAt: collectedAt, quotaUnitsUsed: quotaUsed, evidence: evidence)
            case let .success(data, _):
                guard let page = try? JSONDecoder.youtube.decode(YouTubeSearchPage.self, from: data) else {
                    return unavailable(at: collectedAt, quotaUsed: quotaUsed, evidence: "YouTube returned an invalid search response.")
                }
                items.append(contentsOf: page.items.compactMap {
                    mapVideo(
                        id: $0.id.videoId,
                        snippet: $0.snippet,
                        language: target.language,
                        country: target.country,
                        collectedAt: collectedAt
                    )
                })
                pageToken = page.nextPageToken
                if pageToken == nil { break searchPages }
            }
        }
        return .init(
            items: items,
            state: .available,
            collectedAt: collectedAt,
            quotaUnitsUsed: quotaUsed,
            evidence: "YouTube search returned \(items.count) mapped video item(s) using \(quotaUsed) quota unit(s)."
        )
    }

    func collectComments(video: YouTubeVideoTarget) async -> YouTubeCollection {
        let collectedAt = now()
        guard let credential = await credentialProvider.credential() else {
            return setupRequired(at: collectedAt)
        }
        let baseQuery = [
                .init(name: "part", value: "snippet"),
                .init(name: "videoId", value: video.id),
                .init(name: "order", value: "time"),
                .init(name: "textFormat", value: "plainText"),
                .init(name: "maxResults", value: String(limits.maxItemsPerPage))
            ] as [URLQueryItem]
        var items: [SourceItem] = []
        var pageToken: String?
        var quotaUsed = 0
        commentPages: for _ in 0..<limits.maxPagesPerRequest {
            guard quotaUsed < limits.maxQuotaUnitsPerRun else {
                return quotaBudgetResult(items: items, collectedAt: collectedAt, quotaUsed: quotaUsed)
            }
            var query = baseQuery
            if let pageToken {
                query.append(.init(name: "pageToken", value: pageToken))
            }
            let response = await request(path: "commentThreads", query: query, credential: credential)
            quotaUsed += 1
            switch response {
            case let .failure(state, evidence):
                return .init(items: items, state: state, collectedAt: collectedAt, quotaUnitsUsed: quotaUsed, evidence: evidence)
            case let .success(data, _):
                guard let page = try? JSONDecoder.youtube.decode(YouTubeCommentPage.self, from: data) else {
                    return unavailable(at: collectedAt, quotaUsed: quotaUsed, evidence: "YouTube returned an invalid comment response.")
                }
                items.append(contentsOf: page.items.compactMap {
                    mapComment($0, video: video, collectedAt: collectedAt)
                })
                pageToken = page.nextPageToken
                if pageToken == nil { break commentPages }
            }
        }
        return .init(
            items: items,
            state: .available,
            collectedAt: collectedAt,
            quotaUnitsUsed: quotaUsed,
            evidence: "YouTube returned \(items.count) mapped comment item(s) using \(quotaUsed) quota unit(s)."
        )
    }

    private func collectUploadPlaylist(
        id: String,
        channel: YouTubeMonitoredChannel,
        channelTitle: String,
        credential: YouTubeCredential,
        collectedAt: Date,
        initialQuotaUsed: Int
    ) async -> YouTubeCollection {
        var items: [SourceItem] = []
        var quotaUsed = initialQuotaUsed
        var pageToken: String?

        uploadPages: for _ in 0..<limits.maxPagesPerRequest {
            guard quotaUsed < limits.maxQuotaUnitsPerRun else {
                return quotaBudgetResult(items: items, collectedAt: collectedAt, quotaUsed: quotaUsed)
            }
            var query = [
                URLQueryItem(name: "part", value: "snippet"),
                URLQueryItem(name: "playlistId", value: id),
                URLQueryItem(name: "maxResults", value: String(limits.maxItemsPerPage))
            ]
            if let pageToken {
                query.append(.init(name: "pageToken", value: pageToken))
            }
            let response = await request(path: "playlistItems", query: query, credential: credential)
            quotaUsed += 1
            switch response {
            case let .failure(state, evidence):
                return .init(
                    items: items,
                    state: state,
                    collectedAt: collectedAt,
                    quotaUnitsUsed: quotaUsed,
                    evidence: evidence
                )
            case let .success(data, _):
                guard let page = try? JSONDecoder.youtube.decode(YouTubePlaylistPage.self, from: data) else {
                    return unavailable(
                        at: collectedAt,
                        quotaUsed: quotaUsed,
                        evidence: "YouTube returned an invalid uploads playlist response."
                    )
                }
                items.append(contentsOf: page.items.compactMap {
                    mapVideo(
                        id: $0.snippet.resourceId.videoId,
                        snippet: $0.snippet,
                        language: channel.language,
                        country: channel.country,
                        collectedAt: collectedAt,
                        fallbackAuthor: channelTitle
                    )
                })
                pageToken = page.nextPageToken
                if pageToken == nil { break uploadPages }
            }
        }
        if pageToken != nil, quotaUsed >= limits.maxQuotaUnitsPerRun {
            return quotaBudgetResult(items: items, collectedAt: collectedAt, quotaUsed: quotaUsed)
        }
        return .init(
            items: items,
            state: .available,
            collectedAt: collectedAt,
            quotaUnitsUsed: quotaUsed,
            evidence: "YouTube returned \(items.count) recent video item(s) using \(quotaUsed) quota unit(s)."
        )
    }

    private func request(
        path: String,
        query: [URLQueryItem],
        credential: YouTubeCredential
    ) async -> YouTubeRequestResult {
        var components = URLComponents(
            url: Self.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        var queryItems = query
        var headers = ["Accept": "application/json"]
        switch credential {
        case let .apiKey(key):
            queryItems.append(.init(name: "key", value: key))
        case let .oauthAccessToken(token):
            headers["Authorization"] = "Bearer \(token)"
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            return .failure(.unavailable(statusCode: nil), "The YouTube request could not be constructed.")
        }
        do {
            let response = try await transport.send(.init(url: url, headers: headers, timeout: 15))
            if response.statusCode == 429 || isQuotaExceeded(response.body) {
                return .failure(
                    .rateLimited(retryAfter: retryAfter(response)),
                    "YouTube quota or rate limit reached."
                )
            }
            if response.statusCode == 401 {
                return .failure(
                    .setupRequired,
                    "YouTube authorization expired or was rejected. Reconnect the account."
                )
            }
            guard (200...299).contains(response.statusCode) else {
                return .failure(
                    .unavailable(statusCode: response.statusCode),
                    "YouTube returned HTTP \(response.statusCode)."
                )
            }
            return .success(response.body, response.statusCode)
        } catch {
            return .failure(.unavailable(statusCode: nil), "YouTube could not be reached.")
        }
    }

    private func mapVideo(
        id: String?,
        snippet: YouTubeVideoSnippet,
        language: String,
        country: String,
        collectedAt: Date,
        fallbackAuthor: String? = nil
    ) -> SourceItem? {
        guard let id, !id.isEmpty,
              let publishedAt = ISO8601DateFormatter().date(from: snippet.publishedAt),
              let url = URL(string: "https://www.youtube.com/watch?v=\(id)") else {
            return nil
        }
        return SourceItem(
            id: YouTubeStableID.make(group: .youtube, externalID: id),
            group: .youtube,
            externalID: id,
            title: snippet.title.decodingHTMLEntities,
            summary: snippet.description.decodingHTMLEntities,
            author: snippet.channelTitle.isEmpty ? (fallbackAuthor ?? "Unknown YouTube channel") : snippet.channelTitle,
            url: url,
            publishedAt: publishedAt,
            collectedAt: collectedAt,
            language: language,
            country: country.uppercased(),
            topicKey: YouTubeStableID.topicKey(group: .youtube, externalID: id),
            isOriginalSource: false,
            credibility: 0.65,
            engagement: 0,
            verification: .unverified,
            dataTruth: .live
        )
    }

    private func mapComment(
        _ thread: YouTubeCommentThread,
        video: YouTubeVideoTarget,
        collectedAt: Date
    ) -> SourceItem? {
        let comment = thread.snippet.topLevelComment
        let text = comment.snippet.textOriginal ?? comment.snippet.textDisplay
        guard !text.isEmpty,
              let publishedAt = ISO8601DateFormatter().date(from: comment.snippet.publishedAt),
              let url = URL(string: "https://www.youtube.com/watch?v=\(video.id)&lc=\(comment.id)") else {
            return nil
        }
        return SourceItem(
            id: YouTubeStableID.make(group: .comments, externalID: comment.id),
            group: .comments,
            externalID: comment.id,
            title: text.decodingHTMLEntities,
            summary: "Comment on \(video.channelTitle)",
            author: comment.snippet.authorDisplayName,
            url: url,
            publishedAt: publishedAt,
            collectedAt: collectedAt,
            language: video.language,
            country: video.country.uppercased(),
            topicKey: YouTubeStableID.topicKey(group: .comments, externalID: comment.id),
            isOriginalSource: false,
            credibility: 0.4,
            engagement: comment.snippet.likeCount + thread.snippet.totalReplyCount,
            verification: .unverified,
            dataTruth: .live
        )
    }

    private func setupRequired(at collectedAt: Date) -> YouTubeCollection {
        .init(
            items: [],
            state: .setupRequired,
            collectedAt: collectedAt,
            quotaUnitsUsed: 0,
            evidence: "YouTube Data API credentials are required."
        )
    }

    private func unavailable(at collectedAt: Date, quotaUsed: Int, evidence: String) -> YouTubeCollection {
        .init(
            items: [],
            state: .unavailable(statusCode: nil),
            collectedAt: collectedAt,
            quotaUnitsUsed: quotaUsed,
            evidence: evidence
        )
    }

    private func quotaBudgetResult(
        items: [SourceItem],
        collectedAt: Date,
        quotaUsed: Int
    ) -> YouTubeCollection {
        .init(
            items: items,
            state: .rateLimited(retryAfter: nil),
            collectedAt: collectedAt,
            quotaUnitsUsed: quotaUsed,
            evidence: "The configured YouTube quota budget stopped this collection run."
        )
    }

    private func isQuotaExceeded(_ body: Data) -> Bool {
        guard let error = try? JSONDecoder().decode(YouTubeErrorEnvelope.self, from: body) else {
            return false
        }
        return error.error.errors.contains {
            ["quotaExceeded", "dailyLimitExceeded", "rateLimitExceeded", "userRateLimitExceeded"].contains($0.reason)
        }
    }

    private func retryAfter(_ response: HTTPResponse) -> TimeInterval? {
        response.header("Retry-After").flatMap(TimeInterval.init)
    }
}

private enum YouTubeRequestResult {
    case success(Data, Int)
    case failure(YouTubeCollectionState, String)
}

private extension YouTubeCredential {
    var isOAuth: Bool {
        if case .oauthAccessToken = self { return true }
        return false
    }
}

private struct YouTubeChannelPage: Decodable {
    let items: [Item]

    struct Item: Decodable {
        let id: String
        let snippet: ChannelSnippet
        let contentDetails: ContentDetails
    }

    struct ChannelSnippet: Decodable {
        let title: String
        let description: String
        let country: String?
        let publishedAt: String
    }

    struct ContentDetails: Decodable {
        let relatedPlaylists: RelatedPlaylists
    }

    struct RelatedPlaylists: Decodable {
        let uploads: String
    }
}

private struct YouTubePlaylistPage: Decodable {
    let nextPageToken: String?
    let items: [Item]

    struct Item: Decodable {
        let id: String
        let snippet: YouTubeVideoSnippet
    }
}

private struct YouTubeSearchPage: Decodable {
    let nextPageToken: String?
    let items: [Item]

    struct Item: Decodable {
        let id: Identifier
        let snippet: YouTubeVideoSnippet
    }

    struct Identifier: Decodable {
        let kind: String
        let videoId: String?
    }
}

private struct YouTubeVideoSnippet: Decodable {
    let publishedAt: String
    let channelId: String
    let title: String
    let description: String
    let channelTitle: String
    let resourceId: ResourceIdentifier

    struct ResourceIdentifier: Decodable {
        let kind: String
        let videoId: String?
    }

    private enum CodingKeys: String, CodingKey {
        case publishedAt, channelId, title, description, channelTitle, resourceId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        publishedAt = try container.decode(String.self, forKey: .publishedAt)
        channelId = try container.decode(String.self, forKey: .channelId)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        channelTitle = try container.decodeIfPresent(String.self, forKey: .channelTitle) ?? ""
        resourceId = try container.decodeIfPresent(ResourceIdentifier.self, forKey: .resourceId)
            ?? .init(kind: "youtube#video", videoId: nil)
    }
}

private struct YouTubeCommentPage: Decodable {
    let nextPageToken: String?
    let items: [YouTubeCommentThread]
}

private struct YouTubeCommentThread: Decodable {
    let id: String
    let snippet: ThreadSnippet

    struct ThreadSnippet: Decodable {
        let videoId: String
        let topLevelComment: Comment
        let totalReplyCount: Int
    }

    struct Comment: Decodable {
        let id: String
        let snippet: CommentSnippet
    }

    struct CommentSnippet: Decodable {
        let authorDisplayName: String
        let textDisplay: String
        let textOriginal: String?
        let likeCount: Int
        let publishedAt: String
        let updatedAt: String
    }
}

private struct YouTubeErrorEnvelope: Decodable {
    let error: APIError

    struct APIError: Decodable {
        let errors: [Reason]
    }

    struct Reason: Decodable {
        let reason: String
    }
}

private extension JSONDecoder {
    static var youtube: JSONDecoder {
        JSONDecoder()
    }
}

private extension String {
    var decodingHTMLEntities: String {
        replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}

private enum YouTubeStableID {
    static func make(group: SourceGroup, externalID: String) -> UUID {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in "\(group.rawValue):\(externalID)".utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        let hex = String(format: "%016llx", hash)
        return UUID(uuidString: "00000000-0000-0000-\(hex.prefix(4))-\(hex.suffix(12))")!
    }

    static func topicKey(group: SourceGroup, externalID: String) -> String {
        "unclustered-\(make(group: group, externalID: externalID).uuidString.lowercased())"
    }
}
