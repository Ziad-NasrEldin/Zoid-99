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
        let clusters = Dictionary(grouping: normalized, by: \.topicKey)
        let opportunities = clusters.values.map { makeOpportunity(items: $0, now: now) }
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

    private func normalize(_ items: [SourceItem]) -> [SourceItem] {
        var seen = Set<String>()
        return items
            .sorted { $0.publishedAt < $1.publishedAt }
            .filter { seen.insert("\($0.group.rawValue):\($0.externalID)").inserted }
    }

    private func makeOpportunity(items: [SourceItem], now: Date) -> Opportunity {
        let sorted = items.sorted { $0.publishedAt < $1.publishedAt }
        let original = sorted.first(where: \.isOriginalSource)
        let verified = items.contains(where: { $0.verification == .disputed })
            ? VerificationState.disputed
            : (original != nil && items.contains(where: { $0.verification == .confirmed })
               ? .confirmed : .unverified)
        let ageHours = max(0, now.timeIntervalSince(sorted[0].publishedAt) / 3600)
        let freshness = ageHours < 12 ? 20 : ageHours < 36 ? 14 : 7
        let credibility = Int((items.map(\.credibility).max() ?? 0) * 20)
        let momentum = min(20, items.count * 4 + Int(log10(Double(max(1, items.map(\.engagement).reduce(0, +))))) * 3)
        let creatorActivity = min(10, Set(items.filter { !$0.isOriginalSource }.map(\.author)).count * 3)
        let hasArabic = items.contains { $0.language.hasPrefix("ar") }
        let arabicGap = hasArabic ? 7 : 15
        let regionalCountries = Set(items.map(\.country)).intersection(["EG", "SA", "AE", "OM"])
        let regional = min(15, 7 + regionalCountries.count * 2)
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
                ? "Global AI development with potential Egypt and Gulf relevance; local demand evidence is not yet available."
                : "Signals include \(regionalCountries.sorted().joined(separator: ", ")) and are relevant to Egypt and Gulf audiences.",
            coverageExplanation: hasArabic
                ? "Arabic coverage exists. Review its depth before prioritizing."
                : "No Arabic-language coverage appears in the collected evidence, indicating a strong coverage gap.",
            disposition: .active
        )
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
