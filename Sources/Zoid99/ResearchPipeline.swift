import Foundation

protocol SourceConnector: Sendable {
    var group: SourceGroup { get }
    func collect() async throws -> [SourceItem]
}

enum ConnectorError: Error, Equatable {
    case setupRequired
    case rateLimited
    case unavailable
    case malformedResponse
}

struct FixtureConnector: SourceConnector {
    let group: SourceGroup
    let items: [SourceItem]
    var error: ConnectorError?

    func collect() async throws -> [SourceItem] {
        if let error { throw error }
        guard items.allSatisfy({ $0.group == group }) else { throw ConnectorError.malformedResponse }
        return items
    }
}

struct ResearchPipeline: Sendable {
    func run(items: [SourceItem], now: Date = .now) -> ResearchOutput {
        let normalized = normalize(items)
        let opportunities = storyClusters(normalized).map { makeOpportunity(items: $0, now: now) }
            .sorted { $0.score.total > $1.score.total }
        let comments = clusterComments(normalized.filter { $0.group == .comments })
        let notifications = opportunities.map {
            NotificationRecord(
                id: UUID(),
                opportunityID: $0.id,
                title: $0.title,
                delivery: $0.isHighPriority ? .immediate : .digest,
                createdAt: now,
                isRead: false
            )
        }
        return ResearchOutput(
            normalizedItems: normalized,
            opportunities: opportunities,
            comments: comments,
            notifications: notifications
        )
    }

    func run(
        items: [SourceItem],
        now: Date = .now,
        provider: any AIAnalysisProvider,
        policy: AIAnalysisPolicy = AIAnalysisPolicy()
    ) async -> ResearchOutput {
        var output = run(items: items, now: now)
        let request = makeAIRequest(opportunities: output.opportunities, policy: policy)
        guard !request.clusters.isEmpty else { return output }

        for _ in 0..<policy.maxAttempts {
            do {
                let response = try await provider.analyze(request)
                if let interpretations = AIAnalysisValidator.validate(response, request: request, policy: policy) {
                    output.aiStatus = .applied
                    output.aiInterpretations = interpretations
                    return output
                }
            } catch AIAnalysisProviderError.unavailable {
                output.aiStatus = .unavailableFallback
                return output
            } catch {
                continue
            }
        }

        output.aiStatus = .invalidOutputFallback
        return output
    }

    private func normalize(_ items: [SourceItem]) -> [SourceItem] {
        var seenIDs = Set<String>()
        var seenURLs = Set<String>()
        return items
            .sorted { $0.publishedAt < $1.publishedAt }
            .filter {
                let idKey = "\($0.group.rawValue):\($0.externalID)"
                let urlKey = canonicalURL($0.url)
                return seenIDs.insert(idKey).inserted && seenURLs.insert(urlKey).inserted
            }
    }

    private func storyClusters(_ items: [SourceItem]) -> [[SourceItem]] {
        guard !items.isEmpty else { return [] }
        var parents = Array(items.indices)

        func root(_ index: Int) -> Int {
            var current = index
            while parents[current] != current { current = parents[current] }
            return current
        }

        for left in items.indices {
            for right in items.indices where right > left {
                guard areNearDuplicates(items[left], items[right]) else { continue }
                let leftRoot = root(left)
                let rightRoot = root(right)
                if leftRoot != rightRoot { parents[rightRoot] = leftRoot }
            }
        }

        return Dictionary(grouping: items.indices, by: root)
            .values
            .map { indexes in indexes.map { items[$0] } }
    }

    private func areNearDuplicates(_ left: SourceItem, _ right: SourceItem) -> Bool {
        if normalizedKey(left.topicKey) == normalizedKey(right.topicKey) { return true }
        let leftTokens = significantTokens("\(left.title) \(left.topicKey)")
        let rightTokens = significantTokens("\(right.title) \(right.topicKey)")
        let shared = leftTokens.intersection(rightTokens)
        let denominator = max(1, min(leftTokens.count, rightTokens.count))
        if Double(shared.count) / Double(denominator) >= 0.5 { return true }
        return shared.contains {
            $0.count >= 3 && $0.contains(where: \.isLetter) && $0.contains(where: \.isNumber)
        }
    }

    private func makeOpportunity(items: [SourceItem], now: Date) -> Opportunity {
        let sorted = items.sorted { $0.publishedAt < $1.publishedAt }
        let credibleOriginals = sorted.filter {
            $0.group == .official && $0.isOriginalSource && $0.credibility >= 0.75
        }
        let original = credibleOriginals.first
        let hasCredibleDispute = credibleOriginals.contains { $0.verification == .disputed }
        let hasCredibleConfirmation = credibleOriginals.contains { $0.verification == .confirmed }
        let verified: VerificationState = hasCredibleDispute
            ? .disputed
            : (hasCredibleConfirmation ? .confirmed : .unverified)
        let ageHours = max(0, now.timeIntervalSince(sorted[0].publishedAt) / 3600)
        let freshness = ageHours < 12 ? 20 : ageHours < 36 ? 14 : ageHours < 96 ? 7 : 0
        let credibility = Int((items.map(\.credibility).max() ?? 0) * 20)
        let recentCount = items.filter { now.timeIntervalSince($0.publishedAt) <= 6 * 3_600 }.count
        let priorCount = items.filter {
            let age = now.timeIntervalSince($0.publishedAt)
            return age > 6 * 3_600 && age <= 24 * 3_600
        }.count
        let engagementSignal = Int(log10(Double(max(1, items.map(\.engagement).reduce(0, +)))))
        let momentum = min(20, items.count * 2 + max(0, recentCount - priorCount) * 3 + engagementSignal * 2)
        let creatorActivity = min(10, Set(items.filter { !$0.isOriginalSource }.map(\.author)).count * 3)
        let arabicCount = items.filter { $0.language.lowercased().hasPrefix("ar") }.count
        let arabicGap = arabicCount == 0 ? 15 : arabicCount == 1 ? 9 : 4
        let regionalCountries = Set(items.map { $0.country.uppercased() }).intersection(["EG", "SA", "AE", "OM"])
        let regional = regionalCountries.isEmpty ? 0 : min(15, 5 + regionalCountries.count * 2)
        let score = ScoreBreakdown(
            freshness: freshness,
            credibility: credibility,
            momentum: momentum,
            creatorActivity: creatorActivity,
            arabicCoverageGap: arabicGap,
            regionalRelevance: regional
        )
        let title = original?.title ?? sorted[0].title
        return Opportunity(
            id: stableID(for: sorted[0].topicKey),
            topicKey: sorted[0].topicKey,
            title: title,
            brief: sorted.map(\.summary).first(where: { !$0.isEmpty }) ?? "No summary available.",
            verification: verified,
            earliestPublishedAt: sorted[0].publishedAt,
            originalSource: original,
            items: sorted,
            score: score,
            regionalExplanation: regionalCountries.isEmpty
                ? "No collected evidence currently establishes Egypt, Saudi Arabia, UAE, or Oman relevance."
                : "Collected evidence includes \(regionalCountries.sorted().joined(separator: ", ")); relevance is limited to those cited signals.",
            coverageExplanation: arabicCount > 0
                ? "\(arabicCount) Arabic-language source\(arabicCount == 1 ? "" : "s") found; review depth before treating the gap as closed."
                : "No Arabic-language coverage appears in the collected evidence, indicating a strong coverage gap.",
            disposition: .active
        )
    }

    private func makeAIRequest(opportunities: [Opportunity], policy: AIAnalysisPolicy) -> AIAnalysisRequest {
        var remaining = policy.maxInputItems
        let clusters = opportunities.compactMap { opportunity -> AIAnalysisCluster? in
            guard remaining > 0 else { return nil }
            let sources = opportunity.items.prefix(remaining).map {
                AIAnalysisSource(
                    sourceID: "\($0.group.rawValue):\($0.externalID)",
                    title: String($0.title.prefix(500)),
                    summary: String($0.summary.prefix(1_000)),
                    language: $0.language,
                    country: $0.country
                )
            }
            remaining -= sources.count
            return AIAnalysisCluster(clusterID: opportunity.topicKey, sources: sources)
        }
        return AIAnalysisRequest(
            schemaVersion: 1,
            instruction: "Interpret only the supplied evidence. Cite sourceID values. Do not determine verification, invent facts, or add uncited claims.",
            clusters: clusters
        )
    }

    private func canonicalURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString.lowercased()
        }
        components.fragment = nil
        components.host = components.host?.lowercased()
        if components.path.count > 1 && components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        return components.string ?? url.absoluteString.lowercased()
    }

    private func normalizedKey(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en"))
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private func significantTokens(_ value: String) -> Set<String> {
        let stopwords: Set<String> = [
            "a", "ai", "an", "and", "at", "first", "for", "in", "is", "it", "look",
            "model", "new", "of", "on", "the", "to", "with"
        ]
        let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en"))
        let rawTokens = folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map(normalizedKey)
            .filter { !$0.isEmpty }
        let splitTokens = rawTokens
            .map(normalizedKey)
            .filter { $0.count >= 2 && !stopwords.contains($0) }
        let joinedIdentifiers = zip(rawTokens, rawTokens.dropFirst())
            .map(+)
            .filter {
                $0.count >= 3 && $0.count <= 20 &&
                    $0.contains(where: \.isLetter) && $0.contains(where: \.isNumber)
            }
        let compactTokens = folded.components(separatedBy: .whitespacesAndNewlines)
            .map(normalizedKey)
            .filter { $0.count >= 2 && $0.count <= 40 && !stopwords.contains($0) }
        return Set(splitTokens + compactTokens + joinedIdentifiers)
    }

    private func clusterComments(_ items: [SourceItem]) -> [CommentCluster] {
        Dictionary(grouping: items, by: \.topicKey).values.map { group in
            CommentCluster(
                id: stableID(for: "comment-\(group[0].topicKey)"),
                question: group[0].title,
                count: group.count,
                demand: group.count > 2 ? "High recurring demand" : "Emerging question",
                language: group[0].language,
                sourceItems: group
            )
        }.sorted { $0.count > $1.count }
    }

    private func stableID(for value: String) -> UUID {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        let hex = String(format: "%016llx", hash)
        return UUID(uuidString: "00000000-0000-0000-\(hex.prefix(4))-\(hex.suffix(12))") ?? UUID()
    }
}

enum ResearchFixtures {
    static let now = Date(timeIntervalSince1970: 1_784_764_800)

    static let allSix: [SourceItem] = [
        item(.official, "openai-release", "OpenAI releases a new multimodal model", "Official release details and availability.", "OpenAI", "https://openai.com/news/model", -2, "en", "US", "multimodal-launch", true, 1.0, 8000, .confirmed),
        item(.youtube, "yt-001", "First look at the new multimodal model", "A monitored US creator demonstrates the release.", "AI Explained", "https://youtube.com/watch?v=fixture", -1.5, "en", "US", "multimodal-launch", false, 0.82, 12000, .confirmed),
        item(.googleTrends, "trends-001", "multimodal AI breakout", "Search interest is rising in Egypt and Saudi Arabia.", "Google Trends", "https://trends.google.com/trends/explore?q=multimodal", -1, "en", "EG", "multimodal-launch", false, 0.75, 9000, .confirmed),
        item(.instagram, "ig-001", "Multimodal demo Reel", "A reference creator posts a short product demo.", "Future Tools", "https://instagram.com/p/fixture", -0.8, "en", "AE", "multimodal-launch", false, 0.65, 6200, .unverified),
        item(.comments, "comment-001", "هو الموديل الجديد متاح في مصر؟", "Audience asks whether the product is available in Egypt.", "Viewer", "https://youtube.com/watch?v=own&lc=fixture", -0.5, "ar-EG", "EG", "availability-question", false, 0.55, 41, .unverified),
        item(.comments, "comment-002", "هو الموديل الجديد متاح في مصر؟", "The same availability question appears on another video.", "Viewer 2", "https://youtube.com/watch?v=reference&lc=fixture2", -0.3, "ar-EG", "EG", "availability-question", false, 0.55, 28, .unverified),
        item(.x, "x-001", "Developers report strong multimodal results", "Early discussion adds momentum but is not factual evidence.", "AI Engineer", "https://x.com/example/status/fixture", -1.2, "en", "SA", "multimodal-launch", false, 0.62, 15000, .unverified),
        item(.youtube, "yt-001", "Duplicate fetched video", "Duplicate connector response.", "AI Explained", "https://youtube.com/watch?v=fixture", -1.5, "en", "US", "multimodal-launch", false, 0.82, 12000, .confirmed)
    ]

    private static func item(
        _ group: SourceGroup, _ externalID: String, _ title: String, _ summary: String,
        _ author: String, _ url: String, _ hours: Double, _ language: String,
        _ country: String, _ topic: String, _ original: Bool, _ credibility: Double,
        _ engagement: Int, _ verification: VerificationState
    ) -> SourceItem {
        SourceItem(
            id: UUID(), group: group, externalID: externalID, title: title,
            summary: summary, author: author, url: URL(string: url)!,
            publishedAt: now.addingTimeInterval(hours * 3600), collectedAt: now,
            language: language, country: country, topicKey: topic,
            isOriginalSource: original, credibility: credibility,
            engagement: engagement, verification: verification
        )
    }
}
