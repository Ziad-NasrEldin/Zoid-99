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
    case disconnected = "Disconnected"
    case unavailable = "Unavailable"
    case rateLimited = "Rate limited"
    case delayed = "Delayed"
    case cached = "Cached"
    case unsupported = "Unsupported"
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
    var dispositionUpdatedAt: Date? = nil
    var dispositionMutationID: UUID? = nil

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
        case company = "Company"
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

struct MuteRule: Identifiable, Codable, Hashable, Sendable {
    enum Scope: String, Codable, Sendable {
        case topic
    }

    let id: UUID
    let scope: Scope
    let value: String
    let label: String
    let createdAt: Date
}

enum NotificationPermissionState: String, Codable, Sendable {
    case notDetermined = "Not requested"
    case denied = "Denied"
    case authorized = "Allowed"
    case provisional = "Provisional"
    case unavailable = "Unavailable"
}

struct NotificationRecord: Identifiable, Codable, Hashable, Sendable {
    enum Delivery: String, Codable, Sendable {
        case immediate = "Immediate"
        case digest = "Digest"
    }

    enum DeliveryState: String, Codable, Sendable {
        case awaitingPermission = "Awaiting permission"
        case scheduled = "Scheduled"
        case delivered = "Delivered"
        case suppressed = "Suppressed"
        case failed = "Failed"
    }

    let id: UUID
    let opportunityID: UUID
    let title: String
    let delivery: Delivery
    let createdAt: Date
    var isRead: Bool
    var deliveryState: DeliveryState
    var scheduledAt: Date?
    var deliveredAt: Date?
    var statusDetail: String

    init(
        id: UUID,
        opportunityID: UUID,
        title: String,
        delivery: Delivery,
        createdAt: Date,
        isRead: Bool,
        deliveryState: DeliveryState = .awaitingPermission,
        scheduledAt: Date? = nil,
        deliveredAt: Date? = nil,
        statusDetail: String = "Waiting for notification processing."
    ) {
        self.id = id
        self.opportunityID = opportunityID
        self.title = title
        self.delivery = delivery
        self.createdAt = createdAt
        self.isRead = isRead
        self.deliveryState = deliveryState
        self.scheduledAt = scheduledAt
        self.deliveredAt = deliveredAt
        self.statusDetail = statusDetail
    }

    private enum CodingKeys: String, CodingKey {
        case id, opportunityID, title, delivery, createdAt, isRead
        case deliveryState, scheduledAt, deliveredAt, statusDetail
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        opportunityID = try values.decode(UUID.self, forKey: .opportunityID)
        title = try values.decode(String.self, forKey: .title)
        delivery = try values.decode(Delivery.self, forKey: .delivery)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        isRead = try values.decode(Bool.self, forKey: .isRead)
        deliveryState = try values.decodeIfPresent(DeliveryState.self, forKey: .deliveryState) ?? .awaitingPermission
        scheduledAt = try values.decodeIfPresent(Date.self, forKey: .scheduledAt)
        deliveredAt = try values.decodeIfPresent(Date.self, forKey: .deliveredAt)
        statusDetail = try values.decodeIfPresent(String.self, forKey: .statusDetail)
            ?? "Restored from notification history."
    }
}

struct AppSettings: Codable, Hashable, Sendable {
    var setupComplete: Bool
    var refreshMinutes: Int
    var notificationPermissionRequested: Bool
    var notificationsEnabled: Bool
    var notificationPermission: NotificationPermissionState
    var digestHour: Int
    var discordEnabled: Bool
    var discordHighPriorityEnabled: Bool
    var discordDeliveredOpportunityIDs: Set<UUID>

    static let defaults = AppSettings(
        setupComplete: false,
        refreshMinutes: 15,
        notificationPermissionRequested: false,
        notificationsEnabled: false,
        notificationPermission: .notDetermined,
        digestHour: 18,
        discordEnabled: false,
        discordHighPriorityEnabled: true,
        discordDeliveredOpportunityIDs: []
    )

    init(
        setupComplete: Bool,
        refreshMinutes: Int,
        notificationPermissionRequested: Bool,
        notificationsEnabled: Bool = false,
        notificationPermission: NotificationPermissionState = .notDetermined,
        digestHour: Int = 18,
        discordEnabled: Bool = false,
        discordHighPriorityEnabled: Bool = true,
        discordDeliveredOpportunityIDs: Set<UUID> = []
    ) {
        self.setupComplete = setupComplete
        self.refreshMinutes = refreshMinutes
        self.notificationPermissionRequested = notificationPermissionRequested
        self.notificationsEnabled = notificationsEnabled
        self.notificationPermission = notificationPermission
        self.digestHour = digestHour
        self.discordEnabled = discordEnabled
        self.discordHighPriorityEnabled = discordHighPriorityEnabled
        self.discordDeliveredOpportunityIDs = discordDeliveredOpportunityIDs
    }

    private enum CodingKeys: String, CodingKey {
        case setupComplete, refreshMinutes, notificationPermissionRequested
        case notificationsEnabled, notificationPermission, digestHour
        case discordEnabled, discordHighPriorityEnabled, discordDeliveredOpportunityIDs
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        setupComplete = try values.decode(Bool.self, forKey: .setupComplete)
        refreshMinutes = try values.decode(Int.self, forKey: .refreshMinutes)
        notificationPermissionRequested =
            try values.decodeIfPresent(Bool.self, forKey: .notificationPermissionRequested) ?? false
        notificationsEnabled = try values.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? false
        notificationPermission =
            try values.decodeIfPresent(NotificationPermissionState.self, forKey: .notificationPermission)
            ?? .notDetermined
        digestHour = try values.decodeIfPresent(Int.self, forKey: .digestHour) ?? 18
        discordEnabled = try values.decodeIfPresent(Bool.self, forKey: .discordEnabled) ?? false
        discordHighPriorityEnabled =
            try values.decodeIfPresent(Bool.self, forKey: .discordHighPriorityEnabled) ?? true
        discordDeliveredOpportunityIDs =
            try values.decodeIfPresent(Set<UUID>.self, forKey: .discordDeliveredOpportunityIDs) ?? []
    }
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
    var watchlistNeedsSync: Bool? = false
    var savedOpportunityIDs: Set<UUID>? = []
    var muteRules: [MuteRule]? = []

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
        pendingDispositionMutations: [],
        watchlistNeedsSync: false,
        savedOpportunityIDs: [],
        muteRules: []
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
    case saved = "Saved"
    case radar = "Live Radar"
    case topics = "Topics"
    case comments = "Comments"
    case watchlists = "Watchlists"
    case notifications = "Notifications"
    case settings = "Sources & Settings"

    var id: String { rawValue }
}
