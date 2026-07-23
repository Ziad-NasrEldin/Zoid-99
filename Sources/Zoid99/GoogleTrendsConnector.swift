import Foundation

enum GoogleTrendsRegion: String, CaseIterable, Codable, Sendable {
    case egypt = "EG"
    case saudiArabia = "SA"
    case unitedArabEmirates = "AE"
    case oman = "OM"
    case unitedStates = "US"

    var displayName: String {
        switch self {
        case .egypt: "Egypt"
        case .saudiArabia: "Saudi Arabia"
        case .unitedArabEmirates: "United Arab Emirates"
        case .oman: "Oman"
        case .unitedStates: "United States"
        }
    }
}

struct GoogleTrendsTerm: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case keyword
        case topic
    }

    let kind: Kind
    let value: String
    let label: String

    static func keyword(_ value: String) -> GoogleTrendsTerm {
        GoogleTrendsTerm(kind: .keyword, value: value, label: value)
    }

    static func topic(id: String, label: String) -> GoogleTrendsTerm {
        GoogleTrendsTerm(kind: .topic, value: id, label: label)
    }
}

struct GoogleTrendsTimeRange: Codable, Hashable, Sendable {
    enum Aggregation: String, Codable, Sendable {
        case daily
        case weekly
        case monthly
        case yearly
    }

    let start: Date
    let end: Date
    let aggregation: Aggregation
}

struct GoogleTrendsQuery: Codable, Hashable, Sendable {
    let terms: [GoogleTrendsTerm]
    let regions: [GoogleTrendsRegion]
    let timeRange: GoogleTrendsTimeRange
    let language: String

    init(
        terms: [GoogleTrendsTerm],
        regions: [GoogleTrendsRegion],
        timeRange: GoogleTrendsTimeRange,
        language: String
    ) {
        self.terms = terms
        self.regions = regions
        self.timeRange = timeRange
        self.language = language
    }
}

struct GoogleTrendsInterestPoint: Codable, Hashable, Sendable {
    let term: GoogleTrendsTerm
    let region: GoogleTrendsRegion
    let intervalStart: Date
    let intervalEnd: Date
    let interest: Int
}

struct GoogleTrendsPage: Codable, Hashable, Sendable {
    let points: [GoogleTrendsInterestPoint]
    let nextPageToken: String?
    let dataThrough: Date
}

protocol GoogleTrendsProviding: Sendable {
    func fetch(_ query: GoogleTrendsQuery, pageToken: String?) async throws -> GoogleTrendsPage
}

enum GoogleTrendsProviderError: Error, Equatable, Sendable {
    case rateLimited(retryAfter: TimeInterval?)
    case delayed
    case unavailable
}

enum GoogleTrendsAccess: Sendable {
    case setupRequired
    case configured(provider: any GoogleTrendsProviding)
}

struct GoogleTrendsCollection: Sendable {
    let collection: ConnectorCollection
    let connectionState: ConnectionState
}

struct GoogleTrendsConnector: ProductionSourceConnector {
    let source = OfficialSource(
        id: "google-trends-api-alpha",
        name: "Google Trends API alpha",
        kind: .rss,
        endpoint: URL(string: "https://developers.google.com/search/apis/trends")!,
        homepage: URL(string: "https://trends.google.com/trends/")!,
        language: "und",
        country: "global"
    )

    private let access: GoogleTrendsAccess
    private let defaultQuery: GoogleTrendsQuery
    private let maximumPages: Int
    private let now: @Sendable () -> Date

    init(
        access: GoogleTrendsAccess,
        defaultQuery: GoogleTrendsQuery? = nil,
        maximumPages: Int = 20,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.access = access
        self.maximumPages = max(1, min(maximumPages, 100))
        self.now = now
        let end = now()
        self.defaultQuery = defaultQuery ?? GoogleTrendsQuery(
            terms: [],
            regions: GoogleTrendsRegion.allCases,
            timeRange: .init(
                start: end.addingTimeInterval(-7 * 24 * 60 * 60),
                end: end,
                aggregation: .daily
            ),
            language: "und"
        )
    }

    func collect() async -> ConnectorCollection {
        await collect(defaultQuery).collection
    }

    func collect(_ query: GoogleTrendsQuery) async -> GoogleTrendsCollection {
        let collectedAt = now()
        guard case let .configured(provider) = access else {
            return result(
                items: [],
                state: .unavailable(statusCode: nil),
                connectionState: .setupRequired,
                collectedAt: collectedAt,
                evidence: "Setup required: apply for Google Trends API alpha access and configure the approved provider client."
            )
        }
        guard isValid(query, at: collectedAt) else {
            return result(
                items: [],
                state: .unavailable(statusCode: nil),
                connectionState: .unavailable,
                collectedAt: collectedAt,
                evidence: "The Google Trends request is invalid or exceeds the API alpha's rolling five-year window."
            )
        }

        do {
            var points: [GoogleTrendsInterestPoint] = []
            var pageToken: String?
            var fetchedPages = 0
            repeat {
                let page = try await provider.fetch(query, pageToken: pageToken)
                points.append(contentsOf: page.points)
                pageToken = page.nextPageToken
                fetchedPages += 1
            } while pageToken != nil && fetchedPages < maximumPages

            guard pageToken == nil else {
                return result(
                    items: [],
                    state: .unavailable(statusCode: nil),
                    connectionState: .unavailable,
                    collectedAt: collectedAt,
                    evidence: "The provider returned more than \(maximumPages) pages; collection stopped safely."
                )
            }
            guard !points.isEmpty else {
                return result(
                    items: [],
                    state: .unavailable(statusCode: nil),
                    connectionState: .unavailable,
                    collectedAt: collectedAt,
                    evidence: "The Google Trends API returned no interest points. Missing data is not reported as zero."
                )
            }

            let items = points.map { map($0, language: query.language, collectedAt: collectedAt) }
            return result(
                items: items,
                state: .available,
                connectionState: .connected,
                collectedAt: collectedAt,
                evidence: "\(items.count) Google Trends interest point\(items.count == 1 ? "" : "s") collected through the approved API alpha."
            )
        } catch let error as GoogleTrendsProviderError {
            switch error {
            case let .rateLimited(retryAfter):
                return result(
                    items: [],
                    state: .rateLimited(retryAfter: retryAfter),
                    connectionState: .rateLimited,
                    collectedAt: collectedAt,
                    evidence: "The Google Trends provider rate limit was reached."
                )
            case .delayed:
                return result(
                    items: [],
                    state: .delayed,
                    connectionState: .delayed,
                    collectedAt: collectedAt,
                    evidence: "Google Trends data is delayed; the API alpha normally reports data through two days ago."
                )
            case .unavailable:
                return unavailable(at: collectedAt)
            }
        } catch {
            return unavailable(at: collectedAt)
        }
    }

    private func isValid(_ query: GoogleTrendsQuery, at date: Date) -> Bool {
        !query.terms.isEmpty
            && !query.regions.isEmpty
            && !query.language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && query.terms.allSatisfy {
                !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            && query.timeRange.start < query.timeRange.end
            && query.timeRange.end <= date
            && query.timeRange.start >= date.addingTimeInterval(-1_800 * 24 * 60 * 60)
    }

    private func map(
        _ point: GoogleTrendsInterestPoint,
        language: String,
        collectedAt: Date
    ) -> SourceItem {
        let day = utcDay(point.intervalStart)
        let externalID = "\(point.term.value)|\(point.region.rawValue)|\(day)"
        return SourceItem(
            id: stableID(externalID),
            group: .googleTrends,
            externalID: externalID,
            title: "\(point.term.label) search interest in \(point.region.displayName)",
            summary: "Relative Google search interest: \(point.interest). Interval: \(day). Data source: Google Trends.",
            author: "Google Trends",
            url: exploreURL(for: point.term, region: point.region),
            publishedAt: point.intervalStart,
            collectedAt: collectedAt,
            language: language,
            country: point.region.rawValue,
            topicKey: topicKey(for: point.term),
            isOriginalSource: false,
            credibility: 0.9,
            engagement: max(0, point.interest),
            verification: .unverified,
            dataTruth: .live
        )
    }

    private func exploreURL(for term: GoogleTrendsTerm, region: GoogleTrendsRegion) -> URL {
        var components = URLComponents(string: "https://trends.google.com/trends/explore")!
        components.queryItems = [
            URLQueryItem(name: "geo", value: region.rawValue),
            URLQueryItem(name: "q", value: term.kind == .topic ? term.value : term.label)
        ]
        return components.url!
    }

    private func topicKey(for term: GoogleTrendsTerm) -> String {
        let prefix = term.kind == .topic ? "topic" : "keyword"
        let value = term.value
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "_" }
        return "google-trends-\(prefix)-\(String(value))"
    }

    private func stableID(_ externalID: String) -> UUID {
        var first: UInt64 = 14_695_981_039_346_656_037
        var second: UInt64 = 10_995_116_282_11
        for byte in "google-trends-api-alpha|\(externalID)".utf8 {
            first = (first ^ UInt64(byte)) &* 1_099_511_628_211
            second = (second &* 109_951_162_821) ^ UInt64(byte)
        }
        var bytes = withUnsafeBytes(of: first.bigEndian, Array.init)
        bytes.append(contentsOf: withUnsafeBytes(of: second.bigEndian, Array.init))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private func utcDay(_ date: Date) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0
        )
    }

    private func unavailable(at collectedAt: Date) -> GoogleTrendsCollection {
        result(
            items: [],
            state: .unavailable(statusCode: nil),
            connectionState: .unavailable,
            collectedAt: collectedAt,
            evidence: "The approved Google Trends provider is unavailable. No live data was fabricated."
        )
    }

    private func result(
        items: [SourceItem],
        state: ConnectorCollectionState,
        connectionState: ConnectionState,
        collectedAt: Date,
        evidence: String
    ) -> GoogleTrendsCollection {
        GoogleTrendsCollection(
            collection: ConnectorCollection(
                items: items,
                state: state,
                validators: nil,
                collectedAt: collectedAt,
                evidence: evidence
            ),
            connectionState: connectionState
        )
    }

}
