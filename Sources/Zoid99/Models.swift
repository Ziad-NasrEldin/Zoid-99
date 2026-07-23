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

struct OpportunityDispositionMutation: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let opportunityID: UUID
    let disposition: OpportunityDisposition
    let changedAt: Date
}

struct OpportunityDispositionState: Codable, Hashable, Sendable {
    enum Outcome: String, Codable, Sendable {
        case applied, idempotent, superseded
    }

    let opportunityID: UUID
    let disposition: OpportunityDisposition
    let changedAt: Date
    let mutationID: UUID
    let outcome: Outcome?
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
    var dispositionUpdatedAt: Date? = nil
    var dispositionMutationID: UUID? = nil

    var isHighPriority: Bool { score.total >= 75 && verification == .confirmed }
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
            disposition: disposition,
            dispositionUpdatedAt: dispositionUpdatedAt,
            dispositionMutationID: dispositionMutationID
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
    var pendingDispositionMutations: [OpportunityDispositionMutation]? = []

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
        lastSuccessfulSyncAt: nil,
        pendingDispositionMutations: []
    )
}

struct ResearchOutput: Sendable {
    let normalizedItems: [SourceItem]
    let opportunities: [Opportunity]
    let comments: [CommentCluster]
    let notifications: [NotificationRecord]
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
