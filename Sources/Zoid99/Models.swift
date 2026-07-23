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

    var isHighPriority: Bool { score.total >= 75 && verification == .confirmed }
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
