import Foundation
import UserNotifications

@MainActor
final class AppStore: ObservableObject {
    @Published var selectedDestination: AppDestination = .today
    @Published var selectedOpportunityID: UUID?
    @Published var opportunities: [Opportunity] = []
    @Published var comments: [CommentCluster] = []
    @Published var notifications: [NotificationRecord] = []
    @Published var sourceHealth: [SourceHealth] = []
    @Published var watchlist: [WatchlistEntry] = []
    @Published var radarSource: SourceGroup?
    @Published var radarVerification: VerificationState?
    @Published var searchText = ""
    @Published var setupComplete: Bool
    @Published var refreshMinutes = 15
    @Published var statusMessage = "Ready"
    @Published var isRefreshing = false

    private let defaults: UserDefaults
    private let pipeline = ResearchPipeline()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        setupComplete = defaults.bool(forKey: "setupComplete")
        sourceHealth = SourceGroup.allCases.map {
            SourceHealth(
                group: $0,
                state: .setupRequired,
                lastActivity: nil,
                evidence: "No account or API credential has been connected.",
                repairAction: "Configure"
            )
        }
        watchlist = [
            WatchlistEntry(id: UUID(), kind: .topic, value: "AI agents", highPriority: true),
            WatchlistEntry(id: UUID(), kind: .country, value: "Egypt", highPriority: true),
            WatchlistEntry(id: UUID(), kind: .country, value: "Saudi Arabia", highPriority: false),
            WatchlistEntry(id: UUID(), kind: .language, value: "Arabic", highPriority: true)
        ]
        loadFixtures()
    }

    var selectedOpportunity: Opportunity? {
        opportunities.first { $0.id == selectedOpportunityID }
    }

    var visibleOpportunities: [Opportunity] {
        opportunities.filter { opportunity in
            guard opportunity.disposition != .dismissed, opportunity.disposition != .muted else { return false }
            let sourceMatch = radarSource.map { source in opportunity.items.contains { $0.group == source } } ?? true
            let verificationMatch = radarVerification.map { $0 == opportunity.verification } ?? true
            let searchMatch = searchText.isEmpty
                || opportunity.title.localizedCaseInsensitiveContains(searchText)
                || opportunity.items.contains { $0.summary.localizedCaseInsensitiveContains(searchText) }
            return sourceMatch && verificationMatch && searchMatch
        }
    }

    func loadFixtures() {
        let result = pipeline.run(items: ResearchFixtures.allSix, now: ResearchFixtures.now)
        opportunities = result.opportunities
        comments = result.comments
        notifications = result.notifications
        sourceHealth = SourceGroup.allCases.map { group in
            let count = result.normalizedItems.filter { $0.group == group }.count
            return SourceHealth(
                group: group,
                state: .setupRequired,
                lastActivity: count > 0 ? ResearchFixtures.now : nil,
                evidence: count > 0
                    ? "\(count) deterministic fixture \(count == 1 ? "item" : "items") loaded. Live access is not configured."
                    : "Missing data. Live access is not configured.",
                repairAction: "Configure"
            )
        }
    }

    func refresh() async {
        isRefreshing = true
        statusMessage = "Refreshing"
        try? await Task.sleep(for: .milliseconds(350))
        loadFixtures()
        statusMessage = "Refresh complete"
        isRefreshing = false
    }

    func updateDisposition(_ disposition: OpportunityDisposition, id: UUID) {
        guard let index = opportunities.firstIndex(where: { $0.id == id }) else { return }
        opportunities[index].disposition = disposition
        statusMessage = disposition == .dismissed ? "Opportunity dismissed" : "Opportunity \(disposition.rawValue)"
    }

    func completeSetup() {
        setupComplete = true
        defaults.set(true, forKey: "setupComplete")
        statusMessage = "Setup complete"
    }

    func requestNotifications() async {
        do {
            let allowed = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            statusMessage = allowed ? "Notifications allowed" : "Notifications not allowed"
        } catch {
            statusMessage = "Notification permission error"
        }
    }

    func sendImmediateFixtureNotification() async {
        guard let record = notifications.first(where: { $0.delivery == .immediate }) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Zoid 99 - High-priority opportunity"
        content.body = record.title
        content.sound = .default
        let request = UNNotificationRequest(identifier: record.id.uuidString, content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
            statusMessage = "Test alert delivered"
        } catch {
            statusMessage = "Notification delivery error"
        }
    }
}
