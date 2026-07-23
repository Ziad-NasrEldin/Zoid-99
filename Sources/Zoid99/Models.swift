import Foundation

enum SourceGroup: String, CaseIterable, Codable, Identifiable, Sendable {
    case youtube = "YouTube"
    case googleTrends = "Google Trends"
    case instagram = "Instagram"
    case comments = "Comments"
    case official = "US & Official"
    case x = "X"

    var id: String { rawValue }
}

enum VerificationState: String, CaseIterable, Codable, Sendable {
    case confirmed = "Confirmed"
    case disputed = "Disputed"
    case unverified = "Unverified"
}

enum ConnectionState: String, Codable, Sendable {
    case connected = "Connected"
    case setupRequired = "Setup required"
    case unavailable = "Unavailable"
    case rateLimited = "Rate limited"
    case delayed = "Delayed"
}

enum DataTruth: String, CaseIterable, Codable, Sendable {
    case fixture = "Fixture"
    case cached = "Cached"
    case live = "Live"
    case missing = "Missing"
    case delayed = "Delayed"
    case unavailable = "Unavailable"
    case rateLimited = "Rate limited"

    var isAttentionRequired: Bool {
        self != .live && self != .cached
    }
}

enum OpportunityDisposition: String, Codable, Sendable {
    case active, saved, watched, dismissed, muted
}

struct SourceItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let group: SourceGroup
    let externalID: String
    let title: String
    let summary: String
    let author: String
    let url: URL
    let publishedAt: Date
    let collectedAt: Date
    let language: String
    let country: String
    let topicKey: String
    let isOriginalSource: Bool
    let credibility: Double
    let engagement: Int
    let verification: VerificationState
    var dataTruth: DataTruth = .fixture
}

struct ScoreBreakdown: Codable, Hashable, Sendable {
    let freshness: Int
    let credibility: Int
    let momentum: Int
    let creatorActivity: Int
    let arabicCoverageGap: Int
    let regionalRelevance: Int

    var total: Int {
        freshness + credibility + momentum + creatorActivity + arabicCoverageGap + regionalRelevance
    }
}

struct BriefCitation: Codable, Hashable, Sendable {
    let sourceID: String
    let title: String
    let url: URL
    let publishedAt: Date
}

struct ResearchBrief: Codable, Hashable, Sendable {
    let summary: String
    let originStatement: String
    let citations: [BriefCitation]
}

struct RegionalEvidence: Codable, Hashable, Sendable {
    let countryCode: String
    let sourceCount: Int
}

struct Opportunity: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let topicKey: String
    let title: String
    let brief: String
    let verification: VerificationState
    let earliestPublishedAt: Date
    let originalSource: SourceItem?
    let items: [SourceItem]
    let score: ScoreBreakdown
    let regionalExplanation: String
    let coverageExplanation: String
    var disposition: OpportunityDisposition

    var isHighPriority: Bool {
        score.total >= 75 && score.freshness >= 14 && verification == .confirmed
    }
    var researchBrief: ResearchBrief {
        let sortedItems = items.sorted {
            if $0.publishedAt == $1.publishedAt { return $0.externalID < $1.externalID }
            return $0.publishedAt < $1.publishedAt
        }
        let citations = sortedItems.enumerated().map { _, item in
            BriefCitation(
                sourceID: "\(item.group.rawValue):\(item.externalID)",
                title: item.title,
                url: item.url,
                publishedAt: item.publishedAt
            )
        }
        return ResearchBrief(
            summary: citations.isEmpty ? brief : "\(brief) [1]",
            originStatement: originalSource.map {
                "Earliest credible source: \($0.author), \($0.publishedAt.formatted(.iso8601))."
            } ?? "Earliest credible source is unknown.",
            citations: citations
        )
    }
    var regionalEvidence: [RegionalEvidence] {
        let supported = Set(["EG", "SA", "AE", "OM"])
        return Dictionary(grouping: items.filter { supported.contains($0.country.uppercased()) }) {
            $0.country.uppercased()
        }
        .map { RegionalEvidence(countryCode: $0.key, sourceCount: $0.value.count) }
        .sorted { $0.countryCode < $1.countryCode }
    }
    var momentumEvidence: String {
        let latest = items.map(\.publishedAt).max() ?? earliestPublishedAt
        let recent = items.filter { latest.timeIntervalSince($0.publishedAt) <= 6 * 3_600 }.count
        let earlier = items.count - recent
        return "\(recent) recent signals versus \(earlier) earlier signals."
    }
    var dataTruth: DataTruth {
        if items.contains(where: { $0.dataTruth == .live }) { return .live }
        if items.contains(where: { $0.dataTruth == .cached }) { return .cached }
        if items.contains(where: { $0.dataTruth == .fixture }) { return .fixture }
        if items.contains(where: { $0.dataTruth == .rateLimited }) { return .rateLimited }
        if items.contains(where: { $0.dataTruth == .delayed }) { return .delayed }
        if items.contains(where: { $0.dataTruth == .unavailable }) { return .unavailable }
        return .missing
    }

    func replacingItems(_ items: [SourceItem]) -> Opportunity {
        Opportunity(
            id: id,
            topicKey: topicKey,
            title: title,
            brief: brief,
            verification: verification,
            earliestPublishedAt: earliestPublishedAt,
            originalSource: originalSource.map { original in
                items.first { $0.id == original.id } ?? original
            },
            items: items,
            score: score,
            regionalExplanation: regionalExplanation,
            coverageExplanation: coverageExplanation,
            disposition: disposition
        )
    }
}

struct CommentCluster: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let question: String
    let count: Int
    let demand: String
    let language: String
    let sourceItems: [SourceItem]
}

struct SourceHealth: Identifiable, Codable, Hashable, Sendable {
    var id: SourceGroup { group }
    let group: SourceGroup
    var state: ConnectionState
    var lastActivity: Date?
    var evidence: String
    var repairAction: String
    var dataTruth: DataTruth
}

struct WatchlistEntry: Identifiable, Codable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Codable, Sendable {
        case creator = "Creator"
        case officialSource = "Official source"
        case keyword = "Keyword"
        case topic = "Topic"
        case country = "Country"
        case language = "Language"
    }

    let id: UUID
    let kind: Kind
    var value: String
    var highPriority: Bool
}

struct NotificationRecord: Identifiable, Codable, Hashable, Sendable {
    enum Delivery: String, Codable, Sendable {
        case immediate = "Immediate"
        case digest = "Digest"
    }

    let id: UUID
    let opportunityID: UUID
    let title: String
    let delivery: Delivery
    let createdAt: Date
    var isRead: Bool
}

struct AppSettings: Codable, Hashable, Sendable {
    var setupComplete: Bool
    var refreshMinutes: Int
    var notificationPermissionRequested: Bool

    static let defaults = AppSettings(
        setupComplete: false,
        refreshMinutes: 15,
        notificationPermissionRequested: false
    )
}

struct SourceHealthRecord: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let group: SourceGroup
    let state: ConnectionState
    let dataTruth: DataTruth
    let recordedAt: Date
    let evidence: String
}

struct ResearchState: Codable, Hashable, Sendable {
    var sourceItems: [SourceItem]
    var opportunities: [Opportunity]
    var comments: [CommentCluster]
    var dispositions: [UUID: OpportunityDisposition]
    var watchlist: [WatchlistEntry]
    var settings: AppSettings
    var notificationHistory: [NotificationRecord]
    var sourceHealth: [SourceHealth]
    var sourceHealthHistory: [SourceHealthRecord]
    var lastSuccessfulSyncAt: Date?

    static let empty = ResearchState(
        sourceItems: [],
        opportunities: [],
        comments: [],
        dispositions: [:],
        watchlist: [],
        settings: .defaults,
        notificationHistory: [],
        sourceHealth: [],
        sourceHealthHistory: [],
        lastSuccessfulSyncAt: nil
    )
}

struct ResearchOutput: Sendable {
    let normalizedItems: [SourceItem]
    let opportunities: [Opportunity]
    let comments: [CommentCluster]
    let notifications: [NotificationRecord]
    var aiStatus: AIAnalysisStatus = .notRequested
    var aiInterpretations: [AIClusterInterpretation] = []
}

enum AppDestination: String, CaseIterable, Identifiable {
    case today = "Today"
    case radar = "Live Radar"
    case topics = "Topics"
    case comments = "Comments"
    case watchlists = "Watchlists"
    case notifications = "Notifications"
    case settings = "Sources & Settings"

    var id: String { rawValue }
}
