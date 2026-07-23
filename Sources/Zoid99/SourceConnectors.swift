import Foundation

enum OfficialSourceKind: String, Codable, Sendable {
    case rss
    case atom
    case githubReleases
}

struct OfficialSource: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let kind: OfficialSourceKind
    let endpoint: URL
    let homepage: URL
    let language: String
    let country: String
}

enum ConnectorCollectionState: Equatable, Sendable {
    case available
    case notModified
    case rateLimited(retryAfter: TimeInterval?)
    case unavailable(statusCode: Int?)
    case delayed
}

struct HTTPValidators: Equatable, Sendable {
    let etag: String?
    let lastModified: String?
}

struct ConnectorCollection: Sendable {
    let items: [SourceItem]
    let state: ConnectorCollectionState
    let validators: HTTPValidators?
    let collectedAt: Date
    let evidence: String
}

protocol ProductionSourceConnector: Sendable {
    var source: OfficialSource { get }
    func collect() async -> ConnectorCollection
}

struct HTTPRequest: Equatable, Sendable {
    let url: URL
    var method = "GET"
    var headers: [String: String] = [:]
    var body: Data?
    var timeout: TimeInterval = 15
}

struct HTTPResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data

    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

struct URLSessionHTTPTransport: HTTPTransport {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url, timeoutInterval: request.timeout)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        request.headers.forEach { urlRequest.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw ConnectorError.unavailable }
        let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, entry in
            result[String(describing: entry.key)] = String(describing: entry.value)
        }
        return HTTPResponse(statusCode: http.statusCode, headers: headers, body: data)
    }
}

struct RetryingHTTPTransport: HTTPTransport {
    typealias Sleeper = @Sendable (TimeInterval) async throws -> Void

    let base: any HTTPTransport
    let maximumAttempts: Int
    let sleeper: Sleeper

    init(
        base: any HTTPTransport,
        maximumAttempts: Int = 3,
        sleeper: @escaping Sleeper = { delay in
            try await Task.sleep(for: .seconds(delay))
        }
    ) {
        self.base = base
        self.maximumAttempts = max(1, min(maximumAttempts, 3))
        self.sleeper = sleeper
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var attempt = 1
        while true {
            do {
                let response = try await base.send(request)
                guard response.statusCode == 408 || (500...599).contains(response.statusCode),
                      attempt < maximumAttempts else {
                    return response
                }
                try await sleeper(pow(2, Double(attempt - 1)) * 0.25)
            } catch {
                guard attempt < maximumAttempts, isTransient(error) else { throw error }
                try await sleeper(pow(2, Double(attempt - 1)) * 0.25)
            }
            attempt += 1
        }
    }

    private func isTransient(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return [
            .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
            .networkConnectionLost, .notConnectedToInternet
        ].contains(urlError.code)
    }
}

actor ConnectorHTTPCache {
    struct Entry: Sendable {
        let body: Data
        let validators: HTTPValidators
    }

    private var entries: [URL: Entry] = [:]

    func entry(for url: URL) -> Entry? {
        entries[url]
    }

    func store(_ entry: Entry, for url: URL) {
        entries[url] = entry
    }
}

struct PublicFeedConnector: ProductionSourceConnector {
    let source: OfficialSource
    let transport: any HTTPTransport
    let cache: ConnectorHTTPCache
    let timeout: TimeInterval
    let delayedAfter: TimeInterval
    let now: @Sendable () -> Date

    init(
        source: OfficialSource,
        transport: any HTTPTransport = RetryingHTTPTransport(base: URLSessionHTTPTransport()),
        cache: ConnectorHTTPCache = ConnectorHTTPCache(),
        timeout: TimeInterval = 15,
        delayedAfter: TimeInterval = 7 * 24 * 60 * 60,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.source = source
        self.transport = transport
        self.cache = cache
        self.timeout = timeout
        self.delayedAfter = delayedAfter
        self.now = now
    }

    func collect() async -> ConnectorCollection {
        let collectedAt = now()
        let cached = await cache.entry(for: source.endpoint)
        var headers = [
            "Accept": acceptHeader,
            "User-Agent": "Zoid99/1.0 (+\(source.homepage.absoluteString))"
        ]
        if let etag = cached?.validators.etag { headers["If-None-Match"] = etag }
        if let modified = cached?.validators.lastModified { headers["If-Modified-Since"] = modified }

        do {
            let response = try await transport.send(
                HTTPRequest(url: source.endpoint, headers: headers, timeout: timeout)
            )
            if response.statusCode == 304, let cached {
                return mappedCollection(
                    body: cached.body,
                    state: .notModified,
                    validators: cached.validators,
                    collectedAt: collectedAt
                )
            }
            if response.statusCode == 429
                || (response.statusCode == 403 && response.header("X-RateLimit-Remaining") == "0") {
                return failure(
                    .rateLimited(retryAfter: retryAfter(from: response)),
                    collectedAt: collectedAt,
                    evidence: "The official source returned HTTP \(response.statusCode) with a rate-limit signal."
                )
            }
            guard (200...299).contains(response.statusCode) else {
                return failure(
                    .unavailable(statusCode: response.statusCode),
                    collectedAt: collectedAt,
                    evidence: "The official source returned HTTP \(response.statusCode)."
                )
            }

            let validators = HTTPValidators(
                etag: response.header("ETag"),
                lastModified: response.header("Last-Modified")
            )
            let result = mappedCollection(
                body: response.body,
                state: .available,
                validators: validators,
                collectedAt: collectedAt
            )
            if !result.items.isEmpty {
                await cache.store(.init(body: response.body, validators: validators), for: source.endpoint)
            }
            return result
        } catch {
            return failure(
                .unavailable(statusCode: nil),
                collectedAt: collectedAt,
                evidence: "The official source could not be reached: \(error.localizedDescription)"
            )
        }
    }

    private var acceptHeader: String {
        switch source.kind {
        case .rss, .atom:
            return "application/atom+xml, application/rss+xml, application/xml;q=0.9"
        case .githubReleases:
            return "application/vnd.github+json"
        }
    }

    private func mappedCollection(
        body: Data,
        state: ConnectorCollectionState,
        validators: HTTPValidators?,
        collectedAt: Date
    ) -> ConnectorCollection {
        do {
            let records: [ExternalSourceRecord]
            switch source.kind {
            case .rss, .atom:
                records = try SyndicationParser.parse(body)
            case .githubReleases:
                records = try GitHubReleaseParser.parse(body)
            }
            let items = records.compactMap { record in
                SourceItemMapper.map(record, source: source, collectedAt: collectedAt)
            }
            guard !items.isEmpty else {
                return failure(
                    .unavailable(statusCode: nil),
                    collectedAt: collectedAt,
                    evidence: "The response contained no published source items."
                )
            }
            let resolvedState: ConnectorCollectionState = items.allSatisfy {
                collectedAt.timeIntervalSince($0.publishedAt) > delayedAfter
            } ? .delayed : state
            return ConnectorCollection(
                items: items,
                state: resolvedState,
                validators: validators,
                collectedAt: collectedAt,
                evidence: "\(items.count) published item\(items.count == 1 ? "" : "s") mapped from \(source.name)."
            )
        } catch {
            return failure(
                .unavailable(statusCode: nil),
                collectedAt: collectedAt,
                evidence: "The official source returned a malformed response."
            )
        }
    }

    private func failure(
        _ state: ConnectorCollectionState,
        collectedAt: Date,
        evidence: String
    ) -> ConnectorCollection {
        ConnectorCollection(
            items: [],
            state: state,
            validators: nil,
            collectedAt: collectedAt,
            evidence: evidence
        )
    }

    private func retryAfter(from response: HTTPResponse) -> TimeInterval? {
        if let value = response.header("Retry-After") {
            if let seconds = TimeInterval(value) { return seconds }
            if let date = SourceDateParser.httpDate(value) {
                return max(0, date.timeIntervalSince(now()))
            }
        }
        if let reset = response.header("X-RateLimit-Reset").flatMap(TimeInterval.init) {
            return max(0, reset - now().timeIntervalSince1970)
        }
        return nil
    }
}

private struct ExternalSourceRecord {
    let externalID: String
    let title: String
    let summary: String
    let author: String?
    let url: String
    let publishedAt: Date
    let language: String?
}

private enum SourceItemMapper {
    static func map(
        _ record: ExternalSourceRecord,
        source: OfficialSource,
        collectedAt: Date
    ) -> SourceItem? {
        guard let url = CanonicalURL.normalized(record.url, relativeTo: source.homepage),
              url.scheme == "https" else {
            return nil
        }
        let title = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let externalID = record.externalID.isEmpty ? url.absoluteString : record.externalID
        return SourceItem(
            id: StableSourceID.make(sourceID: source.id, externalID: externalID),
            group: .official,
            externalID: externalID,
            title: title,
            summary: PlainText.fromHTML(record.summary),
            author: record.author.nonEmpty ?? source.name,
            url: url,
            publishedAt: record.publishedAt,
            collectedAt: collectedAt,
            language: record.language.nonEmpty ?? source.language,
            country: source.country,
            topicKey: TopicKey.make(sourceID: source.id, externalID: externalID),
            isOriginalSource: true,
            credibility: 1,
            engagement: 0,
            verification: .confirmed
        )
    }
}

private enum CanonicalURL {
    private static let trackingKeys = Set([
        "fbclid", "gclid", "mc_cid", "mc_eid", "ref", "source",
        "utm_campaign", "utm_content", "utm_medium", "utm_source", "utm_term"
    ])

    static func normalized(_ rawValue: String, relativeTo base: URL) -> URL? {
        guard let resolved = URL(string: rawValue, relativeTo: base)?.absoluteURL,
              var components = URLComponents(url: resolved, resolvingAgainstBaseURL: true) else {
            return nil
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        if (components.scheme == "https" && components.port == 443)
            || (components.scheme == "http" && components.port == 80) {
            components.port = nil
        }
        components.queryItems = components.queryItems?
            .filter { !trackingKeys.contains($0.name.lowercased()) }
            .sorted { $0.name == $1.name ? ($0.value ?? "") < ($1.value ?? "") : $0.name < $1.name }
        if components.queryItems?.isEmpty == true { components.queryItems = nil }
        if components.path.count > 1, components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        return components.url
    }
}

private enum StableSourceID {
    static func make(sourceID: String, externalID: String) -> UUID {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in "\(sourceID):\(externalID)".utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        let hex = String(format: "%016llx", hash)
        return UUID(uuidString: "00000000-0000-0000-\(hex.prefix(4))-\(hex.suffix(12))")!
    }
}

private enum TopicKey {
    static func make(sourceID: String, externalID: String) -> String {
        "unclustered-\(StableSourceID.make(sourceID: sourceID, externalID: externalID).uuidString.lowercased())"
    }
}

private enum PlainText {
    static func fromHTML(_ value: String) -> String {
        value.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private enum SourceDateParser {
    private static let iso8601WithFractional = ISO8601DateFormatter.withFractionalSeconds
    private static let iso8601 = ISO8601DateFormatter()

    static func parse(_ value: String) -> Date? {
        iso8601WithFractional.date(from: value)
            ?? iso8601.date(from: value)
            ?? httpDate(value)
    }

    static func httpDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["EEE, dd MMM yyyy HH:mm:ss zzz", "dd MMM yyyy HH:mm:ss zzz"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}

private extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

private final class SyndicationParser: NSObject, XMLParserDelegate {
    private var records: [ExternalSourceRecord] = []
    private var current: [String: String] = [:]
    private var text = ""
    private var isInsideRecord = false
    private var authorDepth = 0
    private var feedLanguage: String?

    static func parse(_ data: Data) throws -> [ExternalSourceRecord] {
        let delegate = SyndicationParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw ConnectorError.malformedResponse }
        return delegate.records
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = elementName.lowercased()
        text = ""
        if name == "feed" {
            feedLanguage = attributeDict["xml:lang"] ?? attributeDict["lang"]
        }
        if name == "item" || name == "entry" {
            isInsideRecord = true
            current = [:]
        }
        guard isInsideRecord else { return }
        if name == "author" { authorDepth += 1 }
        if name == "link", let href = attributeDict["href"],
           attributeDict["rel"] == nil || attributeDict["rel"] == "alternate" {
            current["link"] = href
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.lowercased()
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !isInsideRecord, name == "language", !value.isEmpty {
            feedLanguage = value
        }
        if isInsideRecord, !value.isEmpty {
            if name == "name", authorDepth > 0 {
                current["author"] = [current["author"], value].compactMap { $0 }.joined(separator: ", ")
            } else if ["guid", "id", "title", "link", "description", "summary", "content",
                       "author", "creator", "pubdate", "published", "updated", "language"].contains(name) {
                current[name] = value
            }
        }
        if name == "author", authorDepth > 0 { authorDepth -= 1 }
        if name == "item" || name == "entry" {
            if let title = current["title"],
               let link = current["link"],
               let dateText = current["pubdate"] ?? current["published"] ?? current["updated"],
               let date = SourceDateParser.parse(dateText) {
                records.append(
                    ExternalSourceRecord(
                        externalID: current["guid"] ?? current["id"] ?? link,
                        title: title,
                        summary: current["description"] ?? current["summary"] ?? current["content"] ?? "",
                        author: current["creator"] ?? current["author"],
                        url: link,
                        publishedAt: date,
                        language: current["language"] ?? feedLanguage
                    )
                )
            }
            current = [:]
            isInsideRecord = false
        }
        text = ""
    }
}

private enum GitHubReleaseParser {
    private struct Release: Decodable {
        struct Author: Decodable { let login: String }
        let id: Int64
        let tagName: String
        let name: String?
        let body: String?
        let htmlURL: String
        let publishedAt: Date?
        let author: Author?
        let draft: Bool

        enum CodingKeys: String, CodingKey {
            case id, name, body, author, draft
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case publishedAt = "published_at"
        }
    }

    static func parse(_ data: Data) throws -> [ExternalSourceRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Release].self, from: data).compactMap { release -> ExternalSourceRecord? in
            guard !release.draft, let publishedAt = release.publishedAt else { return nil }
            return ExternalSourceRecord(
                externalID: String(release.id),
                title: release.name.nonEmpty ?? release.tagName,
                summary: release.body ?? "",
                author: release.author?.login,
                url: release.htmlURL,
                publishedAt: publishedAt,
                language: nil
            )
        }
    }
}

enum OfficialAISourceCatalog {
    static let starter: [OfficialSource] = [
        OfficialSource(
            id: "openai-news",
            name: "OpenAI News",
            kind: .rss,
            endpoint: URL(string: "https://openai.com/news/rss.xml")!,
            homepage: URL(string: "https://openai.com/news/")!,
            language: "en",
            country: "US"
        ),
        OfficialSource(
            id: "huggingface-transformers-releases",
            name: "Hugging Face Transformers Releases",
            kind: .githubReleases,
            endpoint: URL(string: "https://api.github.com/repos/huggingface/transformers/releases?per_page=30")!,
            homepage: URL(string: "https://github.com/huggingface/transformers")!,
            language: "en",
            country: "US"
        ),
        OfficialSource(
            id: "arxiv-cs-ai",
            name: "arXiv Computer Science - Artificial Intelligence",
            kind: .atom,
            endpoint: URL(
                string: "https://export.arxiv.org/api/query?search_query=cat%3Acs.AI&start=0&max_results=30&sortBy=submittedDate&sortOrder=descending"
            )!,
            homepage: URL(string: "https://arxiv.org/list/cs.AI/recent")!,
            language: "en",
            country: "US"
        )
    ]
}
