import Foundation

struct WatchlistConnectorPlan: Equatable, Sendable {
    let creators: [String]
    let officialSourceURLs: [URL]
    let searchTerms: [String]
    let countryCodes: [String]
    let languageCodes: [String]

    init(entries: [WatchlistEntry]) {
        creators = Self.values(.creator, in: entries)
        officialSourceURLs = Self.values(.officialSource, in: entries).compactMap(URL.init(string:))
        searchTerms = [.company, .keyword, .topic]
            .flatMap { Self.values($0, in: entries) }
            .uniquedCaseInsensitive()
        countryCodes = Self.values(.country, in: entries)
            .compactMap(Self.countryCode)
            .uniquedCaseInsensitive()
        languageCodes = Self.values(.language, in: entries)
            .compactMap(Self.languageCode)
            .uniquedCaseInsensitive()
    }

    var xUsernames: [String] {
        creators.map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: "@ ").union(.whitespacesAndNewlines))
        }
    }

    var xQueries: [String] {
        let languages = languageCodes.isEmpty ? [nil] : languageCodes.map(Optional.some)
        return searchTerms.flatMap { term in
            languages.map { language in
                guard let language else { return term }
                return "\(term) lang:\(language)"
            }
        }
    }

    var youtubeChannels: [YouTubeMonitoredChannel] {
        let locales = providerLocales
        return creators.compactMap { creator -> String? in
            let trimmed = creator.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.hasPrefix("UC") && trimmed.count == 24 ? trimmed : nil
        }.flatMap { channelID in
            locales.map { locale in
                .reference(id: channelID, language: locale.language, country: locale.country)
            }
        }
    }

    var youtubeSearches: [YouTubeSearchTarget] {
        let channelIDs = Set(youtubeChannels.compactMap(\.id))
        let terms = searchTerms + creators.filter { !channelIDs.contains($0) }
        return terms.uniquedCaseInsensitive().flatMap { term in
            providerLocales.map { locale in
                YouTubeSearchTarget(query: term, language: locale.language, country: locale.country)
            }
        }.prefix(50).map { $0 }
    }

    var trendTerms: [GoogleTrendsTerm] {
        searchTerms.prefix(5).map(GoogleTrendsTerm.keyword)
    }

    var trendRegions: [GoogleTrendsRegion] {
        let selected = countryCodes.compactMap(GoogleTrendsRegion.init(rawValue:))
        return selected.isEmpty ? GoogleTrendsRegion.allCases : selected
    }

    var trendLanguages: [String] {
        languageCodes.isEmpty ? ["und"] : languageCodes
    }

    private var providerLocales: [(country: String, language: String)] {
        let countries = countryCodes.isEmpty ? ["US"] : countryCodes
        let languages = languageCodes.isEmpty ? ["en"] : languageCodes
        return countries.flatMap { country in
            languages.map { language in (country, language) }
        }
    }

    private static func values(_ kind: WatchlistEntry.Kind, in entries: [WatchlistEntry]) -> [String] {
        entries
            .filter { $0.kind == kind }
            .sorted { $0.highPriority && !$1.highPriority }
            .map { $0.value.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniquedCaseInsensitive()
    }

    private static func countryCode(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let known = [
            "egypt": "EG", "مصر": "EG",
            "saudi arabia": "SA", "السعودية": "SA",
            "united arab emirates": "AE", "uae": "AE", "الإمارات": "AE",
            "oman": "OM", "عمان": "OM",
            "united states": "US", "usa": "US", "us": "US"
        ]
        if let code = known[normalized] { return code }
        guard normalized.range(of: #"^[a-z]{2}$"#, options: .regularExpression) != nil else { return nil }
        return normalized.uppercased()
    }

    private static func languageCode(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let known = [
            "arabic": "ar", "العربية": "ar",
            "english": "en", "الإنجليزية": "en"
        ]
        if let code = known[normalized] { return code }
        guard normalized.range(of: #"^[a-z]{2,3}$"#, options: .regularExpression) != nil else { return nil }
        return normalized
    }
}

enum WatchlistConnectorFactory {
    static func connectors(
        for entries: [WatchlistEntry],
        environment: [String: String],
        credentialStore: any CredentialStoring = KeychainCredentialStore()
    ) -> [GroupedSourceConnector] {
        let plan = WatchlistConnectorPlan(entries: entries)
        let storedYouTube = try? credentialStore.credential(provider: .youtube)
        let storedInstagram = try? credentialStore.credential(provider: .meta)
        let storedX = try? credentialStore.credential(provider: .x)
        var result = plan.officialSourceURLs.enumerated().map { index, url in
            GroupedSourceConnector(
                group: .official,
                connector: PublicFeedConnector(
                    source: OfficialSource(
                        id: "watchlist-\(index)-\(url.absoluteString)",
                        name: url.host ?? url.absoluteString,
                        kind: .rss,
                        endpoint: url,
                        homepage: url,
                        language: plan.languageCodes.first ?? "und",
                        country: plan.countryCodes.first ?? "global"
                    )
                )
            )
        }

        if !plan.youtubeChannels.isEmpty || !plan.youtubeSearches.isEmpty {
            let credential: YouTubeCredential?
            if let oauth = environment["ZOID99_YOUTUBE_OAUTH_ACCESS_TOKEN"].nonEmpty {
                credential = .oauthAccessToken(oauth)
            } else if let apiKey = environment["ZOID99_YOUTUBE_API_KEY"].nonEmpty {
                credential = .apiKey(apiKey)
            } else if let apiKey = storedYouTube.nonEmpty {
                credential = .apiKey(apiKey)
            } else {
                credential = nil
            }
            let connector = YouTubeDataConnector(
                credentialProvider: StaticYouTubeCredentialProvider(credential)
            )
            result.append(
                GroupedSourceConnector(
                    group: .youtube,
                    connector: WatchlistYouTubeConnector(
                        connector: connector,
                        channels: plan.youtubeChannels,
                        searches: plan.youtubeSearches
                    )
                )
            )
            result.append(
                GroupedSourceConnector(
                    group: .comments,
                    connector: WatchlistYouTubeCommentsConnector(
                        connector: connector,
                        channels: plan.youtubeChannels,
                        searches: plan.youtubeSearches
                    )
                )
            )
        }

        if !plan.xUsernames.isEmpty || !plan.xQueries.isEmpty {
            var xEnvironment = environment
            if xEnvironment["ZOID99_X_BEARER_TOKEN"].nonEmpty == nil, let storedX = storedX.nonEmpty {
                xEnvironment["ZOID99_X_BEARER_TOKEN"] = storedX
            }
            result.append(
                GroupedSourceConnector(
                    group: .x,
                    connector: XAPIConnector(
                        configuration: .fromEnvironment(
                            xEnvironment,
                            monitoredUsernames: plan.xUsernames,
                            recentSearchQueries: plan.xQueries
                        )
                    )
                )
            )
        }

        if !plan.creators.isEmpty || environment["ZOID99_INSTAGRAM_ACCOUNT_ID"].nonEmpty != nil {
            let token = (
                environment["ZOID99_INSTAGRAM_ACCESS_TOKEN"].nonEmpty ?? storedInstagram.nonEmpty
            ).map(InstagramAccessToken.init)
            result.append(
                GroupedSourceConnector(
                    group: .instagram,
                    connector: WatchlistInstagramConnector(
                        connector: InstagramGraphConnector(
                            configuration: InstagramConnectorConfiguration(
                                graphAPIVersion: environment["ZOID99_INSTAGRAM_GRAPH_API_VERSION"] ?? "",
                                accessToken: token,
                                selectedProfessionalAccountID: environment["ZOID99_INSTAGRAM_ACCOUNT_ID"].nonEmpty,
                                referenceUsernames: plan.creators
                            )
                        )
                    )
                )
            )
        }

        if !plan.trendTerms.isEmpty {
            let now = Date.now
            result.append(contentsOf: plan.trendLanguages.map { language in
                GroupedSourceConnector(
                    group: .googleTrends,
                    connector: GoogleTrendsConnector(
                        access: .setupRequired,
                        defaultQuery: GoogleTrendsQuery(
                            terms: plan.trendTerms,
                            regions: plan.trendRegions,
                            timeRange: GoogleTrendsTimeRange(
                                start: now.addingTimeInterval(-7 * 24 * 60 * 60),
                                end: now,
                                aggregation: .daily
                            ),
                            language: language
                        )
                    )
                )
            })
        }

        return result
    }
}

struct WatchlistYouTubeCommentsConnector: ProductionSourceConnector {
    let source = OfficialSource(
        id: "youtube-comments-api-v3-watchlist",
        name: "YouTube Data API v3 Comments",
        kind: .rss,
        endpoint: URL(string: "https://www.googleapis.com/youtube/v3/commentThreads")!,
        homepage: URL(string: "https://youtube.com")!,
        language: "und",
        country: "global"
    )
    let connector: YouTubeDataConnector
    let channels: [YouTubeMonitoredChannel]
    let searches: [YouTubeSearchTarget]

    func collect() async -> ConnectorCollection {
        var discovery: [YouTubeCollection] = []
        for channel in channels {
            discovery.append(await connector.collectRecentVideos(channel: channel))
        }
        for search in searches {
            discovery.append(await connector.search(search))
        }
        let videos = discovery.flatMap(\.items).uniquedSourceItems().prefix(10)
        guard !videos.isEmpty else {
            return ConnectorCollection(
                items: [],
                state: .unavailable(statusCode: nil),
                validators: nil,
                collectedAt: discovery.map(\.collectedAt).max() ?? .now,
                evidence: discovery.map(\.evidence).joined(separator: " ")
            )
        }
        var commentCollections: [YouTubeCollection] = []
        for video in videos {
            commentCollections.append(
                await connector.collectComments(
                    video: YouTubeVideoTarget(
                        id: video.externalID,
                        channelKind: .reference,
                        channelTitle: video.author,
                        language: video.language,
                        country: video.country
                    )
                )
            )
        }
        let comments = commentCollections.flatMap(\.items).uniquedSourceItems()
        return ConnectorCollection(
            items: comments,
            state: Self.state(commentCollections.map(\.state)),
            validators: nil,
            collectedAt: commentCollections.map(\.collectedAt).max() ?? .now,
            evidence: commentCollections.map(\.evidence).joined(separator: " ")
        )
    }

    private static func state(_ states: [YouTubeCollectionState]) -> ConnectorCollectionState {
        if states.contains(.available) {
            return .available
        }
        if let limited = states.first(where: {
            if case .rateLimited = $0 { return true }
            return false
        }), case let .rateLimited(retryAfter) = limited {
            return .rateLimited(retryAfter: retryAfter)
        }
        return .unavailable(statusCode: nil)
    }
}

private struct WatchlistYouTubeConnector: ProductionSourceConnector {
    let source = OfficialSource(
        id: "youtube-data-api-v3-watchlist",
        name: "YouTube Data API v3",
        kind: .rss,
        endpoint: URL(string: "https://www.googleapis.com/youtube/v3")!,
        homepage: URL(string: "https://youtube.com")!,
        language: "und",
        country: "global"
    )
    let connector: YouTubeDataConnector
    let channels: [YouTubeMonitoredChannel]
    let searches: [YouTubeSearchTarget]

    func collect() async -> ConnectorCollection {
        var results: [YouTubeCollection] = []
        for channel in channels {
            results.append(await connector.collectRecentVideos(channel: channel))
        }
        for search in searches {
            results.append(await connector.search(search))
        }
        return Self.collection(results)
    }

    private static func collection(_ results: [YouTubeCollection]) -> ConnectorCollection {
        let items = results.flatMap(\.items).uniquedSourceItems()
        let state: ConnectorCollectionState
        if let limited = results.first(where: {
            if case .rateLimited = $0.state { return true }
            return false
        }), case let .rateLimited(retryAfter) = limited.state {
            state = .rateLimited(retryAfter: retryAfter)
        } else if results.contains(where: { $0.state == .available }) {
            state = .available
        } else if results.contains(where: { $0.state == .setupRequired }) {
            state = .unavailable(statusCode: nil)
        } else {
            state = .unavailable(statusCode: nil)
        }
        return ConnectorCollection(
            items: items,
            state: state,
            validators: nil,
            collectedAt: results.map(\.collectedAt).max() ?? .now,
            evidence: results.map(\.evidence).joined(separator: " ")
        )
    }
}

private struct WatchlistInstagramConnector: ProductionSourceConnector {
    let source = OfficialSource(
        id: "instagram-graph-api-watchlist",
        name: "Instagram Graph API",
        kind: .rss,
        endpoint: URL(string: "https://graph.facebook.com")!,
        homepage: URL(string: "https://instagram.com")!,
        language: "und",
        country: "global"
    )
    let connector: InstagramGraphConnector

    func collect() async -> ConnectorCollection {
        let result = await connector.collect()
        let state: ConnectorCollectionState
        switch result.state {
        case .available:
            state = .available
        case let .rateLimited(retryAfter):
            state = .rateLimited(retryAfter: retryAfter)
        case let .unavailable(_, statusCode):
            state = .unavailable(statusCode: statusCode)
        case .setupRequired, .unsupported:
            state = .unavailable(statusCode: nil)
        }
        return ConnectorCollection(
            items: result.items,
            state: state,
            validators: nil,
            collectedAt: result.collectedAt,
            evidence: result.evidence.joined(separator: " ")
        )
    }
}

private extension Array where Element == String {
    func uniquedCaseInsensitive() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0.lowercased()).inserted }
    }
}

private extension Array where Element == SourceItem {
    func uniquedSourceItems() -> [SourceItem] {
        var seen = Set<String>()
        return filter { seen.insert("\($0.group.rawValue):\($0.externalID)").inserted }
    }
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
