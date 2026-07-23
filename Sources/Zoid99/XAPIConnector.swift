import Foundation

enum XAPIAuthentication: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    case bearerToken(String)
    case oauth2AccessToken(String)

    fileprivate var authorizationHeader: String {
        switch self {
        case let .bearerToken(token), let .oauth2AccessToken(token):
            return "Bearer \(token)"
        }
    }

    var description: String { "[redacted X API credential]" }
    var debugDescription: String { description }
}

struct XAPIConfiguration: Sendable {
    let authentication: XAPIAuthentication?
    let monitoredUsernames: [String]
    let listIDs: [String]
    let recentSearchQueries: [String]

    init(
        authentication: XAPIAuthentication?,
        monitoredUsernames: [String] = [],
        listIDs: [String] = [],
        recentSearchQueries: [String] = []
    ) {
        self.authentication = authentication
        self.monitoredUsernames = Self.uniqueValidUsernames(monitoredUsernames)
        self.listIDs = Self.uniqueNumericValues(listIDs)
        self.recentSearchQueries = Self.uniqueNonEmptyValues(recentSearchQueries)
    }

    static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment,
        monitoredUsernames: [String] = [],
        listIDs: [String] = [],
        recentSearchQueries: [String] = []
    ) -> XAPIConfiguration {
        let authentication: XAPIAuthentication?
        if let token = environment["ZOID99_X_OAUTH2_ACCESS_TOKEN"]?.nonEmpty {
            authentication = .oauth2AccessToken(token)
        } else if let token = environment["ZOID99_X_BEARER_TOKEN"]?.nonEmpty {
            authentication = .bearerToken(token)
        } else {
            authentication = nil
        }
        return XAPIConfiguration(
            authentication: authentication,
            monitoredUsernames: monitoredUsernames,
            listIDs: listIDs,
            recentSearchQueries: recentSearchQueries
        )
    }

    fileprivate var hasTargets: Bool {
        !monitoredUsernames.isEmpty || !listIDs.isEmpty || !recentSearchQueries.isEmpty
    }

    private static func uniqueValidUsernames(_ values: [String]) -> [String] {
        uniqueNonEmptyValues(values).filter {
            $0.range(of: #"^[A-Za-z0-9_]{1,15}$"#, options: .regularExpression) != nil
        }
    }

    private static func uniqueNumericValues(_ values: [String]) -> [String] {
        uniqueNonEmptyValues(values).filter {
            $0.range(of: #"^[0-9]{1,19}$"#, options: .regularExpression) != nil
        }
    }

    private static func uniqueNonEmptyValues(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
    }
}

enum XConnectorState: Equatable, Sendable {
    case available
    case setupRequired
    case rateLimited(retryAfter: TimeInterval?)
    case delayed
    case unavailable(statusCode: Int?)
}

enum XReferenceType: String, Codable, Sendable {
    case repliedTo = "replied_to"
    case quoted
    case retweeted
}

struct XPostReference: Equatable, Sendable {
    let type: XReferenceType
    let postID: String
}

struct XPostEngagement: Equatable, Sendable {
    let reposts: Int
    let replies: Int
    let likes: Int
    let quotes: Int
    let bookmarks: Int
    let impressions: Int?

    var observableInteractions: Int {
        reposts + replies + likes + quotes + bookmarks
    }
}

struct XRateLimit: Equatable, Sendable {
    let limit: Int?
    let remaining: Int?
    let resetAt: Date?
}

struct XCollectionReport: Sendable {
    let collection: ConnectorCollection
    let state: XConnectorState
    let engagement: [String: XPostEngagement]
    let references: [String: [XPostReference]]
    let rateLimit: XRateLimit?
}

actor XSinceIDStore {
    private var values: [String: String]

    init(initialValues: [String: String] = [:]) {
        values = initialValues
    }

    func sinceID(for target: String) -> String? {
        values[target]
    }

    func save(_ sinceID: String, for target: String) {
        values[target] = sinceID
    }
}

struct XAPIConnector: ProductionSourceConnector {
    let source = OfficialSource(
        id: "x-api-v2",
        name: "X API v2",
        kind: .rss,
        endpoint: URL(string: "https://api.x.com/2/tweets/search/recent")!,
        homepage: URL(string: "https://x.com")!,
        language: "und",
        country: "Global"
    )

    private let configuration: XAPIConfiguration
    private let transport: any HTTPTransport
    private let checkpoints: XSinceIDStore
    private let maximumPagesPerTarget: Int
    private let timeout: TimeInterval
    private let delayedAfter: TimeInterval
    private let now: @Sendable () -> Date

    init(
        configuration: XAPIConfiguration,
        transport: any HTTPTransport = RetryingHTTPTransport(base: URLSessionHTTPTransport()),
        checkpoints: XSinceIDStore = XSinceIDStore(),
        maximumPagesPerTarget: Int = 2,
        timeout: TimeInterval = 15,
        delayedAfter: TimeInterval = 24 * 60 * 60,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.configuration = configuration
        self.transport = transport
        self.checkpoints = checkpoints
        self.maximumPagesPerTarget = max(1, min(maximumPagesPerTarget, 10))
        self.timeout = timeout
        self.delayedAfter = delayedAfter
        self.now = now
    }

    func collect() async -> ConnectorCollection {
        await collectReport().collection
    }

    func collectReport() async -> XCollectionReport {
        let collectedAt = now()
        guard let authentication = configuration.authentication, configuration.hasTargets else {
            return report(
                items: [],
                state: .setupRequired,
                collectedAt: collectedAt,
                evidence: "X API setup is required. Configure one read credential and at least one account, List, or search query."
            )
        }

        var accumulator = XAccumulator()
        do {
            if !configuration.monitoredUsernames.isEmpty {
                for start in stride(from: 0, to: configuration.monitoredUsernames.count, by: 100) {
                    let end = min(start + 100, configuration.monitoredUsernames.count)
                    let lookup = try await lookupUsers(
                        Array(configuration.monitoredUsernames[start..<end]),
                        authentication: authentication
                    )
                    accumulator.capture(lookup.response)
                    accumulator.hadAPIErrors = accumulator.hadAPIErrors || lookup.hadErrors
                    if let terminal = terminalState(for: lookup.response, collectedAt: collectedAt) {
                        return terminal
                    }
                    for user in lookup.users {
                        let target = XTarget.user(user)
                        if let terminal = try await collect(
                            target: target,
                            authentication: authentication,
                            collectedAt: collectedAt,
                            accumulator: &accumulator
                        ) {
                            return terminal
                        }
                    }
                }
            }

            for listID in configuration.listIDs {
                if let terminal = try await collect(
                    target: .list(id: listID),
                    authentication: authentication,
                    collectedAt: collectedAt,
                    accumulator: &accumulator
                ) {
                    return terminal
                }
            }

            for query in configuration.recentSearchQueries {
                if let terminal = try await collect(
                    target: .search(query: query),
                    authentication: authentication,
                    collectedAt: collectedAt,
                    accumulator: &accumulator
                ) {
                    return terminal
                }
            }
        } catch {
            return report(
                items: [],
                state: .unavailable(statusCode: nil),
                collectedAt: collectedAt,
                evidence: "The official X API could not be reached.",
                rateLimit: accumulator.rateLimit
            )
        }

        let items = accumulator.posts.values
            .compactMap { map($0.post, users: accumulator.users, collectedAt: collectedAt) }
            .sorted {
                if $0.publishedAt == $1.publishedAt { return $0.externalID > $1.externalID }
                return $0.publishedAt > $1.publishedAt
            }
        if items.isEmpty, accumulator.hadAPIErrors {
            return report(
                items: [],
                state: .unavailable(statusCode: nil),
                collectedAt: collectedAt,
                evidence: "The official X API returned errors and no usable public posts.",
                rateLimit: accumulator.rateLimit
            )
        }
        let isDelayed = accumulator.isTruncated
            || (!items.isEmpty && items.allSatisfy {
                collectedAt.timeIntervalSince($0.publishedAt) > delayedAfter
            })
        let state: XConnectorState = isDelayed ? .delayed : .available
        return report(
            items: items,
            state: state,
            collectedAt: collectedAt,
            evidence: "\(items.count) public post\(items.count == 1 ? "" : "s") collected from the official X API.",
            engagement: accumulator.engagement,
            references: accumulator.references,
            rateLimit: accumulator.rateLimit
        )
    }

    private func collect(
        target: XTarget,
        authentication: XAPIAuthentication,
        collectedAt: Date,
        accumulator: inout XAccumulator
    ) async throws -> XCollectionReport? {
        let sinceID = target.supportsSinceID ? await checkpoints.sinceID(for: target.key) : nil
        var nextToken: String?
        var firstPageNewestID: String?

        var drainedAllPages = false
        for pageIndex in 0..<maximumPagesPerTarget {
            let request = try request(
                for: target,
                authentication: authentication,
                sinceID: sinceID,
                nextToken: nextToken
            )
            let response = try await transport.send(request)
            accumulator.capture(response)
            if let terminal = terminalState(for: response, collectedAt: collectedAt) {
                return terminal
            }

            let page = try XResponseDecoder.page(from: response.body)
            if firstPageNewestID == nil { firstPageNewestID = page.meta?.newestID }
            accumulator.capture(page)
            guard let token = page.meta?.nextToken?.nonEmpty else {
                drainedAllPages = true
                break
            }
            if pageIndex == maximumPagesPerTarget - 1 {
                accumulator.isTruncated = true
                break
            }
            nextToken = token
        }

        if let newestID = firstPageNewestID, target.supportsSinceID, drainedAllPages {
            await checkpoints.save(newestID, for: target.key)
        }
        return nil
    }

    private func lookupUsers(
        _ usernames: [String],
        authentication: XAPIAuthentication
    ) async throws -> (users: [XUser], response: HTTPResponse, hadErrors: Bool) {
        var components = URLComponents(string: "https://api.x.com/2/users/by")!
        components.queryItems = [
            URLQueryItem(name: "usernames", value: usernames.prefix(100).joined(separator: ",")),
            URLQueryItem(name: "user.fields", value: "id,name,username")
        ]
        let response = try await transport.send(
            HTTPRequest(
                url: components.url!,
                headers: headers(authentication),
                timeout: timeout
            )
        )
        guard (200...299).contains(response.statusCode) else { return ([], response, false) }
        let decoded = try XResponseDecoder.users(from: response.body)
        return (decoded.users, response, decoded.hadErrors)
    }

    private func request(
        for target: XTarget,
        authentication: XAPIAuthentication,
        sinceID: String?,
        nextToken: String?
    ) throws -> HTTPRequest {
        var components = URLComponents(url: target.endpoint, resolvingAgainstBaseURL: false)!
        var queryItems = [
            URLQueryItem(name: "max_results", value: "100"),
            URLQueryItem(
                name: "tweet.fields",
                value: "id,text,author_id,created_at,lang,public_metrics,referenced_tweets"
            ),
            URLQueryItem(name: "expansions", value: target.expansions),
            URLQueryItem(name: "user.fields", value: "id,name,username")
        ]
        if case let .search(query) = target {
            queryItems.insert(URLQueryItem(name: "query", value: query), at: 0)
        }
        if let sinceID { queryItems.append(URLQueryItem(name: "since_id", value: sinceID)) }
        if let nextToken { queryItems.append(URLQueryItem(name: "next_token", value: nextToken)) }
        components.queryItems = queryItems
        guard let url = components.url else { throw ConnectorError.malformedResponse }
        return HTTPRequest(url: url, headers: headers(authentication), timeout: timeout)
    }

    private func headers(_ authentication: XAPIAuthentication) -> [String: String] {
        [
            "Accept": "application/json",
            "Authorization": authentication.authorizationHeader,
            "User-Agent": "Zoid99/1.0"
        ]
    }

    private func terminalState(
        for response: HTTPResponse,
        collectedAt: Date
    ) -> XCollectionReport? {
        if response.statusCode == 429 {
            let retryAfter = XRateLimitParser.retryAfter(response, now: collectedAt)
            return report(
                items: [],
                state: .rateLimited(retryAfter: retryAfter),
                collectedAt: collectedAt,
                evidence: "The official X API rate limit or usage cap was reached.",
                rateLimit: XRateLimitParser.parse(response)
            )
        }
        guard (200...299).contains(response.statusCode) else {
            return report(
                items: [],
                state: .unavailable(statusCode: response.statusCode),
                collectedAt: collectedAt,
                evidence: "The official X API returned HTTP \(response.statusCode). Check access, credits, and endpoint permissions.",
                rateLimit: XRateLimitParser.parse(response)
            )
        }
        return nil
    }

    private func map(_ post: XPost, users: [String: XUser], collectedAt: Date) -> SourceItem? {
        guard let publishedAt = XResponseDecoder.date(post.createdAt) else { return nil }
        let username = post.authorID.flatMap { users[$0]?.username } ?? "i"
        guard let url = URL(string: "https://x.com/\(username)/status/\(post.id)") else { return nil }
        let engagement = XPostEngagement(post.publicMetrics).observableInteractions
        return SourceItem(
            id: XStableID.make(post.id),
            group: .x,
            externalID: post.id,
            title: post.text.singleLine.prefixText(120),
            summary: post.text.singleLine,
            author: username == "i" ? (post.authorID ?? "Unknown X author") : "@\(username)",
            url: url,
            publishedAt: publishedAt,
            collectedAt: collectedAt,
            language: post.lang?.nonEmpty ?? "und",
            country: "Global",
            topicKey: "unclustered-x-\(post.id)",
            isOriginalSource: true,
            credibility: 0.6,
            engagement: engagement,
            verification: .unverified,
            dataTruth: .live
        )
    }

    private func report(
        items: [SourceItem],
        state: XConnectorState,
        collectedAt: Date,
        evidence: String,
        engagement: [String: XPostEngagement] = [:],
        references: [String: [XPostReference]] = [:],
        rateLimit: XRateLimit? = nil
    ) -> XCollectionReport {
        let connectorState: ConnectorCollectionState
        switch state {
        case .available:
            connectorState = .available
        case .delayed:
            connectorState = .delayed
        case let .rateLimited(retryAfter):
            connectorState = .rateLimited(retryAfter: retryAfter)
        case let .unavailable(statusCode):
            connectorState = .unavailable(statusCode: statusCode)
        case .setupRequired:
            connectorState = .unavailable(statusCode: nil)
        }
        return XCollectionReport(
            collection: ConnectorCollection(
                items: items,
                state: connectorState,
                validators: nil,
                collectedAt: collectedAt,
                evidence: evidence
            ),
            state: state,
            engagement: engagement,
            references: references,
            rateLimit: rateLimit
        )
    }
}

private enum XTarget {
    case user(XUser)
    case list(id: String)
    case search(query: String)

    var key: String {
        switch self {
        case let .user(user): return "user:\(user.id)"
        case let .list(id): return "list:\(id)"
        case let .search(query): return "search:\(query)"
        }
    }

    var endpoint: URL {
        switch self {
        case let .user(user): return URL(string: "https://api.x.com/2/users/\(user.id)/tweets")!
        case let .list(id): return URL(string: "https://api.x.com/2/lists/\(id)/tweets")!
        case .search: return URL(string: "https://api.x.com/2/tweets/search/recent")!
        }
    }

    var supportsSinceID: Bool {
        switch self {
        case .user, .search: return true
        case .list: return false
        }
    }

    var expansions: String {
        switch self {
        case .list:
            return "author_id"
        case .user, .search:
            return "author_id,referenced_tweets.id,referenced_tweets.id.author_id"
        }
    }
}

private struct XAccumulator {
    var posts: [String: (post: XPost, isReference: Bool)] = [:]
    var users: [String: XUser] = [:]
    var engagement: [String: XPostEngagement] = [:]
    var references: [String: [XPostReference]] = [:]
    var rateLimit: XRateLimit?
    var isTruncated = false
    var hadAPIErrors = false

    mutating func capture(_ response: HTTPResponse) {
        if let parsed = XRateLimitParser.parse(response) { rateLimit = parsed }
    }

    mutating func capture(_ page: XPage) {
        hadAPIErrors = hadAPIErrors || !(page.errors?.isEmpty ?? true)
        for user in page.includes?.users ?? [] { users[user.id] = user }
        for post in page.data ?? [] { capture(post, isReference: false) }
        for post in page.includes?.tweets ?? [] { capture(post, isReference: true) }
    }

    private mutating func capture(_ post: XPost, isReference: Bool) {
        if posts[post.id] == nil || !isReference {
            posts[post.id] = (post, isReference)
        }
        engagement[post.id] = XPostEngagement(post.publicMetrics)
        references[post.id] = post.referencedTweets?.map {
            XPostReference(type: $0.type, postID: $0.id)
        } ?? []
    }
}

private struct XPage: Decodable {
    struct Includes: Decodable {
        let users: [XUser]?
        let tweets: [XPost]?
    }

    struct Meta: Decodable {
        let newestID: String?
        let oldestID: String?
        let resultCount: Int?
        let nextToken: String?

        enum CodingKeys: String, CodingKey {
            case newestID = "newest_id"
            case oldestID = "oldest_id"
            case resultCount = "result_count"
            case nextToken = "next_token"
        }
    }

    let data: [XPost]?
    let includes: Includes?
    let meta: Meta?
    let errors: [XProblem]?
}

private struct XPost: Decodable {
    struct Metrics: Decodable {
        let retweetCount: Int?
        let replyCount: Int?
        let likeCount: Int?
        let quoteCount: Int?
        let bookmarkCount: Int?
        let impressionCount: Int?

        enum CodingKeys: String, CodingKey {
            case retweetCount = "retweet_count"
            case replyCount = "reply_count"
            case likeCount = "like_count"
            case quoteCount = "quote_count"
            case bookmarkCount = "bookmark_count"
            case impressionCount = "impression_count"
        }
    }

    struct Reference: Decodable {
        let type: XReferenceType
        let id: String
    }

    let id: String
    let text: String
    let authorID: String?
    let createdAt: String
    let lang: String?
    let publicMetrics: Metrics?
    let referencedTweets: [Reference]?

    enum CodingKeys: String, CodingKey {
        case id, text, lang
        case authorID = "author_id"
        case createdAt = "created_at"
        case publicMetrics = "public_metrics"
        case referencedTweets = "referenced_tweets"
    }
}

private struct XUser: Decodable {
    let id: String
    let name: String
    let username: String
}

private struct XProblem: Decodable {
    let title: String?
    let detail: String?
}

private extension XPostEngagement {
    init(_ metrics: XPost.Metrics?) {
        reposts = metrics?.retweetCount ?? 0
        replies = metrics?.replyCount ?? 0
        likes = metrics?.likeCount ?? 0
        quotes = metrics?.quoteCount ?? 0
        bookmarks = metrics?.bookmarkCount ?? 0
        impressions = metrics?.impressionCount
    }
}

private enum XResponseDecoder {
    private struct UsersResponse: Decodable {
        let data: [XUser]?
        let errors: [XProblem]?
    }

    static func page(from data: Data) throws -> XPage {
        try JSONDecoder().decode(XPage.self, from: data)
    }

    static func users(from data: Data) throws -> (users: [XUser], hadErrors: Bool) {
        let response = try JSONDecoder().decode(UsersResponse.self, from: data)
        return (response.data ?? [], !(response.errors?.isEmpty ?? true))
    }

    static func date(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private enum XRateLimitParser {
    static func parse(_ response: HTTPResponse) -> XRateLimit? {
        let limit = response.header("x-rate-limit-limit").flatMap(Int.init)
        let remaining = response.header("x-rate-limit-remaining").flatMap(Int.init)
        let resetAt = response.header("x-rate-limit-reset")
            .flatMap(TimeInterval.init)
            .map(Date.init(timeIntervalSince1970:))
        guard limit != nil || remaining != nil || resetAt != nil else { return nil }
        return XRateLimit(limit: limit, remaining: remaining, resetAt: resetAt)
    }

    static func retryAfter(_ response: HTTPResponse, now: Date) -> TimeInterval? {
        if let seconds = response.header("Retry-After").flatMap(TimeInterval.init) {
            return max(0, seconds)
        }
        guard let reset = parse(response)?.resetAt else { return nil }
        return max(0, reset.timeIntervalSince(now))
    }
}

private enum XStableID {
    static func make(_ value: String) -> UUID {
        var first: UInt64 = 14_695_981_039_346_656_037
        var second: UInt64 = 10_995_116_282_111
        for byte in value.utf8 {
            first = (first ^ UInt64(byte)) &* 1_099_511_628_211
            second = (second ^ UInt64(byte)) &* 14_029_467_366_897_019_727
        }
        let bytes = withUnsafeBytes(of: first.bigEndian, Array.init)
            + withUnsafeBytes(of: second.bigEndian, Array.init)
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var singleLine: String {
        components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    func prefixText(_ maximumLength: Int) -> String {
        guard count > maximumLength else { return self }
        return String(prefix(maximumLength - 1)) + "…"
    }
}
