import SwiftUI

struct MainShellView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selection: AppDestination? = .today

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ZOID 99")
                        .font(SumiFont.display(24))
                    Text("RESEARCH INTELLIGENCE")
                        .font(SumiFont.meta(9))
                        .tracking(1.8)
                        .foregroundStyle(SumiColor.mutedInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .overlay(alignment: .bottom) { Divider().overlay(SumiColor.rule) }

                List(AppDestination.allCases, selection: $selection) { destination in
                    SidebarRow(destination: destination, selected: selection == destination)
                        .tag(destination)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(SumiColor.softPaper)

                HStack {
                    Circle()
                        .fill(SumiColor.seal)
                        .frame(width: 7, height: 7)
                    Text(store.statusMessage.uppercased())
                        .font(SumiFont.meta(9))
                        .tracking(1)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .overlay(alignment: .top) { Divider().overlay(SumiColor.rule) }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 240)
        } detail: {
            destinationView(selection ?? .today)
        }
        .onChange(of: selection) { _, value in
            if let value { store.selectedDestination = value }
        }
    }

    @ViewBuilder
    private func destinationView(_ destination: AppDestination) -> some View {
        switch destination {
        case .today: TodayView()
        case .radar: RadarView()
        case .topics: TopicsView()
        case .comments: CommentsView()
        case .watchlists: WatchlistsView()
        case .notifications: NotificationsView()
        case .settings: SettingsView()
        }
    }
}

private struct SidebarRow: View {
    let destination: AppDestination
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(selected ? SumiColor.seal : Color.clear)
                .frame(width: 2, height: 18)
            Text(destination.rawValue.uppercased())
                .font(SumiFont.meta(11))
                .tracking(1.2)
            Spacer()
        }
        .foregroundStyle(selected ? SumiColor.paper : SumiColor.ink)
        .padding(.vertical, 7)
        .padding(.horizontal, 7)
        .background(selected ? SumiColor.ink : Color.clear)
        .contentShape(Rectangle())
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

struct TodayView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .top) {
                    LedgerHeader(
                        eyebrow: "Daily briefing",
                        title: "Today",
                        subtitle: "Trustworthy developments ranked for freshness, evidence, and Arabic opportunity."
                    )
                    Spacer()
                    Button(store.isRefreshing ? "Refreshing" : "Refresh") {
                        Task { await store.refresh() }
                    }
                    .buttonStyle(SumiButtonStyle(primary: true))
                    .disabled(store.isRefreshing)
                }
                Divider().overlay(SumiColor.ink)

                HStack(spacing: 0) {
                    Metric(value: "\(store.visibleOpportunities.count)", label: "Active opportunities")
                    Metric(value: "\(store.visibleOpportunities.filter(\.isHighPriority).count)", label: "Immediate alerts")
                    Metric(value: "\(store.sourceHealth.filter { $0.state == .connected }.count)/6", label: "Live sources")
                    Metric(value: store.dataTruth.rawValue, label: "Current evidence")
                }

                SectionTitle("PRIORITY LEDGER")
                ForEach(store.visibleOpportunities) { opportunity in
                    OpportunityRow(opportunity: opportunity)
                }

                SectionTitle("SOURCE HEALTH SUMMARY")
                SourceHealthLedger(compact: true)
            }
            .padding(30)
        }
        .sumiPage()
    }
}

private struct Metric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(SumiFont.display(25))
            Text(label.uppercased())
                .font(SumiFont.meta(9))
                .tracking(1.2)
                .foregroundStyle(SumiColor.mutedInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(SumiColor.softPaper)
        .overlay(Rectangle().stroke(SumiColor.rule, lineWidth: 0.5))
    }
}

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(SumiFont.meta(11))
            .tracking(1.8)
            .foregroundStyle(SumiColor.mutedInk)
    }
}

struct OpportunityRow: View {
    @EnvironmentObject private var store: AppStore
    let opportunity: Opportunity

    var body: some View {
        Button {
            store.selectedOpportunityID = opportunity.id
        } label: {
            HStack(alignment: .top, spacing: 16) {
                Rectangle()
                    .fill(opportunity.isHighPriority ? SumiColor.seal : SumiColor.ink)
                    .frame(width: 2)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        StateLabel(text: opportunity.verification.rawValue, urgent: opportunity.verification != .confirmed)
                        StateLabel(text: opportunity.dataTruth.rawValue, urgent: opportunity.dataTruth.isAttentionRequired)
                        if opportunity.isHighPriority { StateLabel(text: "High priority", urgent: true) }
                        Spacer()
                        Text(opportunity.earliestPublishedAt, style: .relative)
                            .font(SumiFont.meta(10))
                            .foregroundStyle(SumiColor.mutedInk)
                    }
                    Text(opportunity.title)
                        .font(SumiFont.display(20))
                        .multilineTextAlignment(.leading)
                    Text(opportunity.brief)
                        .font(SumiFont.body())
                        .foregroundStyle(SumiColor.mutedInk)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 14) {
                        Text("SCORE \(opportunity.score.total)")
                        Text("\(opportunity.items.count) SOURCES")
                        Text(opportunity.coverageExplanation)
                            .lineLimit(1)
                    }
                    .font(SumiFont.meta(9))
                    .tracking(0.8)
                    .foregroundStyle(SumiColor.mutedInk)
                }
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Divider().overlay(SumiColor.rule) }
        .sheet(isPresented: Binding(
            get: { store.selectedOpportunityID == opportunity.id },
            set: { if !$0 { store.selectedOpportunityID = nil } }
        )) {
            OpportunityDetailView(opportunityID: opportunity.id)
        }
    }
}

struct RadarView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LedgerHeader(
                eyebrow: "Six-source chronology",
                title: "Live Radar",
                subtitle: "Everything collected, with duplicates combined before ranking."
            )
            HStack(spacing: 10) {
                TextField("Search evidence", text: $store.searchText)
                    .textFieldStyle(.plain)
                    .padding(9)
                    .overlay(Rectangle().stroke(SumiColor.ink, lineWidth: 1))
                Picker("Source", selection: $store.radarSource) {
                    Text("All sources").tag(SourceGroup?.none)
                    ForEach(SourceGroup.allCases) { Text($0.rawValue).tag(Optional($0)) }
                }
                Picker("Verification", selection: $store.radarVerification) {
                    Text("All states").tag(VerificationState?.none)
                    ForEach(VerificationState.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                }
                Button("Clear") {
                    store.searchText = ""
                    store.radarSource = nil
                    store.radarVerification = nil
                }
                .buttonStyle(SumiButtonStyle())
            }
            Divider().overlay(SumiColor.ink)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(store.visibleOpportunities) { OpportunityRow(opportunity: $0) }
                }
            }
        }
        .padding(30)
        .sumiPage()
    }
}

struct TopicsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var topicQuery = ""

    var filtered: [Opportunity] {
        topicQuery.isEmpty ? store.visibleOpportunities : store.visibleOpportunities.filter {
            $0.title.localizedCaseInsensitiveContains(topicQuery) || $0.topicKey.localizedCaseInsensitiveContains(topicQuery)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LedgerHeader(
                eyebrow: "Cross-source research",
                title: "Topics",
                subtitle: "Compare global evidence, creator coverage, and Arabic-market gaps."
            )
            TextField("Research a topic across connected sources", text: $topicQuery)
                .textFieldStyle(.plain)
                .padding(10)
                .overlay(Rectangle().stroke(SumiColor.ink, lineWidth: 1))
            Divider().overlay(SumiColor.ink)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filtered) { OpportunityRow(opportunity: $0) }
                }
            }
        }
        .padding(30)
        .sumiPage()
    }
}

struct CommentsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LedgerHeader(
                eyebrow: "Audience demand",
                title: "Comments",
                subtitle: "Recurring questions and confusion from owned and reference channels."
            )
            Divider().overlay(SumiColor.ink)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.comments) { cluster in
                        HStack(alignment: .top, spacing: 18) {
                            Text("\(cluster.count)")
                                .font(SumiFont.display(28))
                                .frame(width: 42, alignment: .leading)
                            VStack(alignment: .leading, spacing: 7) {
                                Text(cluster.question)
                                    .font(SumiFont.body(17))
                                    .environment(\.layoutDirection, cluster.language.hasPrefix("ar") ? .rightToLeft : .leftToRight)
                                    .frame(maxWidth: .infinity, alignment: cluster.language.hasPrefix("ar") ? .trailing : .leading)
                                HStack {
                                    StateLabel(text: cluster.demand)
                                    Text("\(cluster.sourceItems.count) EVIDENCE LINKS")
                                        .font(SumiFont.meta(9))
                                        .foregroundStyle(SumiColor.mutedInk)
                                }
                            }
                        }
                        .padding(.vertical, 16)
                        .overlay(alignment: .bottom) { Divider().overlay(SumiColor.rule) }
                    }
                }
            }
        }
        .padding(30)
        .sumiPage()
    }
}

struct WatchlistsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var newValue = ""
    @State private var kind: WatchlistEntry.Kind = .keyword

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LedgerHeader(
                eyebrow: "Monitoring scope",
                title: "Watchlists",
                subtitle: "Creators, official sources, keywords, topics, countries, and languages."
            )
            HStack {
                Picker("Type", selection: $kind) {
                    ForEach(WatchlistEntry.Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                TextField("Add a watchlist value", text: $newValue)
                    .textFieldStyle(.plain)
                    .padding(9)
                    .overlay(Rectangle().stroke(SumiColor.ink, lineWidth: 1))
                Button("Add") {
                    guard !newValue.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    store.addWatchlist(kind: kind, value: newValue)
                    newValue = ""
                }
                .buttonStyle(SumiButtonStyle(primary: true))
            }
            Divider().overlay(SumiColor.ink)
            List {
                ForEach(store.watchlist) { entry in
                    HStack {
                        Text(entry.kind.rawValue.uppercased())
                            .font(SumiFont.meta(9))
                            .frame(width: 110, alignment: .leading)
                        Text(entry.value).font(SumiFont.body())
                        Spacer()
                        Toggle(
                            "High priority",
                            isOn: Binding(
                                get: { entry.highPriority },
                                set: { store.setWatchlistPriority(id: entry.id, highPriority: $0) }
                            )
                        )
                            .toggleStyle(.checkbox)
                    }
                    .padding(.vertical, 7)
                }
                .onDelete(perform: store.removeWatchlist)
            }
            .listStyle(.plain)
        }
        .padding(30)
        .sumiPage()
    }
}

struct NotificationsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LedgerHeader(
                eyebrow: "Alert ledger",
                title: "Notifications",
                subtitle: "Immediate interruption for strong opportunities; everything else enters a digest."
            )
            HStack {
                Button("Allow notifications") { Task { await store.requestNotifications() } }
                    .buttonStyle(SumiButtonStyle(primary: true))
                Button("Send demo alert") { Task { await store.sendImmediateDemoNotification() } }
                    .buttonStyle(SumiButtonStyle(urgent: true))
            }
            Divider().overlay(SumiColor.ink)
            List(store.notifications) { record in
                HStack(alignment: .top) {
                    StateLabel(text: record.delivery.rawValue, urgent: record.delivery == .immediate)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(record.title).font(SumiFont.body(15))
                        Text(record.createdAt, style: .relative)
                            .font(SumiFont.meta(9))
                            .foregroundStyle(SumiColor.mutedInk)
                    }
                    Spacer()
                }
                .padding(.vertical, 7)
            }
            .listStyle(.plain)
        }
        .padding(30)
        .sumiPage()
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                LedgerHeader(
                    eyebrow: "Operational truth",
                    title: "Sources & Settings",
                    subtitle: "Connection health, evidence, repair actions, refresh, and privacy."
                )
                Divider().overlay(SumiColor.ink)
                SectionTitle("EXTERNAL PROVIDER CONNECTIONS")
                ProviderConnectionsLedger()
                SectionTitle("SOURCE HEALTH")
                SourceHealthLedger(compact: false)
                SectionTitle("REFRESH & PRIVACY")
                VStack(alignment: .leading, spacing: 14) {
                    Stepper(
                        "Refresh every \(store.refreshMinutes) minutes",
                        value: Binding(
                            get: { store.refreshMinutes },
                            set: store.setRefreshMinutes
                        ),
                        in: 5...60,
                        step: 5
                    )
                    Text("Research, dispositions, watchlists, settings, notification history, and source health are stored locally for offline access. Live account tokens must be stored in macOS Keychain when connectors are configured.")
                        .font(SumiFont.body())
                        .foregroundStyle(SumiColor.mutedInk)
                    Text("Always-on monitoring while this Mac sleeps requires a separately deployed service. It is not active in the local fixture mode.")
                        .font(SumiFont.body())
                        .foregroundStyle(SumiColor.sealDeep)
                }
                .padding(16)
                .background(SumiColor.softPaper)
                .overlay(Rectangle().stroke(SumiColor.rule, lineWidth: 1))
            }
            .padding(30)
        }
        .sumiPage()
    }
}

struct SourceHealthLedger: View {
    @EnvironmentObject private var store: AppStore
    let compact: Bool
    @State private var selectedProvider: ExternalProvider?

    var body: some View {
        VStack(spacing: 0) {
            if !compact {
                HStack {
                    Text("SOURCE").frame(width: 150, alignment: .leading)
                    Text("STATE").frame(width: 120, alignment: .leading)
                    Text("LAST ACTIVITY").frame(width: 140, alignment: .leading)
                    Text("EVIDENCE")
                    Spacer()
                    Text("REPAIR")
                }
                .font(SumiFont.meta(9))
                .tracking(1)
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) { Divider().overlay(SumiColor.ink) }
            }
            ForEach(store.sourceHealth) { health in
                HStack(alignment: .top, spacing: 12) {
                    Text(health.group.rawValue)
                        .font(SumiFont.body())
                        .frame(width: compact ? 125 : 150, alignment: .leading)
                    StateLabel(text: health.state.rawValue, urgent: health.state != .connected)
                        .frame(width: compact ? 110 : 120, alignment: .leading)
                    StateLabel(text: health.dataTruth.rawValue, urgent: health.dataTruth.isAttentionRequired)
                        .frame(width: compact ? 90 : 100, alignment: .leading)
                    if !compact {
                        Group {
                            if let activity = health.lastActivity {
                                Text(activity, style: .relative)
                            } else {
                                Text("Missing")
                            }
                        }
                        .font(SumiFont.meta(9))
                        .frame(width: 140, alignment: .leading)
                    }
                    Text(health.evidence)
                        .font(SumiFont.body(12))
                        .foregroundStyle(SumiColor.mutedInk)
                        .lineLimit(compact ? 1 : 3)
                    Spacer()
                    if !compact {
                        Button(health.repairAction) {
                            selectedProvider = health.group == .comments
                                ? .youtube
                                : ExternalProvider.allCases.first { $0.sourceGroup == health.group }
                        }
                        .buttonStyle(SumiButtonStyle())
                    }
                }
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) { Divider().overlay(SumiColor.rule) }
            }
        }
        .sheet(item: $selectedProvider) { provider in
            ProviderConnectionSheet(provider: provider)
                .environmentObject(store)
        }
    }
}

private struct ProviderConnectionsLedger: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedProvider: ExternalProvider?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("PROVIDER")
                Spacer()
                Text("ACTION")
            }
            .font(SumiFont.meta(9))
            .tracking(1)
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) { Divider().overlay(SumiColor.ink) }

            ForEach(store.providerConnections) { connection in
                let definition = ProviderDefinition.catalog.first { $0.provider == connection.provider }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 12) {
                        Text(connection.provider.rawValue)
                            .font(SumiFont.body())
                            .frame(width: 150, alignment: .leading)
                        StateLabel(text: connection.state.rawValue, urgent: connection.state.needsAttention)
                        Spacer()
                        Button(connection.repairAction) {
                            selectedProvider = connection.provider
                        }
                        .buttonStyle(SumiButtonStyle())
                        .disabled(connection.state == .validating)
                    }
                    HStack(spacing: 18) {
                        Text("CREDENTIAL  \(definition?.credentialBoundary.rawValue ?? "Unsupported")")
                        Group {
                            if let activity = connection.lastActivity {
                                Text("LAST ACTIVITY  \(activity.formatted(date: .abbreviated, time: .shortened))")
                            } else {
                                Text("LAST ACTIVITY  No verified activity")
                            }
                        }
                    }
                    .font(SumiFont.meta(9))
                    .tracking(0.5)
                    Text(connection.evidence)
                        .font(SumiFont.body(12))
                        .foregroundStyle(SumiColor.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) { Divider().overlay(SumiColor.rule) }
            }
        }
        .sheet(item: $selectedProvider) { provider in
            ProviderConnectionSheet(provider: provider)
                .environmentObject(store)
        }
    }
}

private struct ProviderConnectionSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let provider: ExternalProvider
    @State private var credential = ""

    private var definition: ProviderDefinition {
        ProviderDefinition.catalog.first { $0.provider == provider }!
    }

    private var connection: ProviderConnection? {
        store.providerConnections.first { $0.provider == provider }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                LedgerHeader(
                    eyebrow: "External authorization only",
                    title: provider.rawValue,
                    subtitle: "This does not create or sign in to a Zoid 99 account."
                )
                Spacer()
                Button("Close") { dismiss() }.buttonStyle(SumiButtonStyle())
            }
            Divider().overlay(SumiColor.ink)
            if let connection {
                HStack {
                    StateLabel(text: connection.state.rawValue, urgent: connection.state.needsAttention)
                    Text(connection.evidence)
                        .font(SumiFont.body(12))
                        .foregroundStyle(SumiColor.mutedInk)
                }
            }
            connectionDetails
            if definition.credentialBoundary == .keychain {
                VStack(alignment: .leading, spacing: 7) {
                    Text("PROVIDER CREDENTIAL").font(SumiFont.meta(9)).tracking(1)
                    SecureField("Paste credential", text: $credential)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .overlay(Rectangle().stroke(SumiColor.rule))
                    Text("The value is sent directly to macOS Keychain. It is never displayed again or written to app logs.")
                        .font(SumiFont.body(12))
                        .foregroundStyle(SumiColor.mutedInk)
                }
            }
            HStack {
                Button(definition.credentialBoundary == .serverSecret ? "Check server status" : "Validate again") {
                    Task { await store.validateConnection(provider) }
                }
                if definition.credentialBoundary == .keychain {
                    Button("Save & validate") {
                        let submitted = credential
                        credential = ""
                        Task { await store.connect(provider, credential: submitted) }
                    }
                    .buttonStyle(SumiButtonStyle(primary: true))
                    Button("Disconnect") {
                        credential = ""
                        Task { await store.disconnect(provider) }
                    }
                    .buttonStyle(SumiButtonStyle(urgent: true))
                }
            }
            .buttonStyle(SumiButtonStyle())
        }
        .padding(30)
        .frame(minWidth: 720, maxWidth: 720, minHeight: 500)
        .background(SumiColor.paper)
    }

    private var connectionDetails: some View {
        VStack(spacing: 0) {
            detailRow("PREREQUISITE", definition.prerequisite)
            detailRow("PERMISSION SCOPE", definition.permissionScope)
            detailRow("CREDENTIAL LOCATION", definition.credentialBoundary.rawValue)
            detailRow("SETUP", definition.setupGuidance)
        }
        .overlay(Rectangle().stroke(SumiColor.rule))
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(label)
                .font(SumiFont.meta(9))
                .tracking(1)
                .frame(width: 150, alignment: .leading)
            Text(value).font(SumiFont.body())
            Spacer()
        }
        .padding(12)
        .overlay(alignment: .bottom) { Divider().overlay(SumiColor.rule) }
    }
}

struct OpportunityDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let opportunityID: UUID

    var opportunity: Opportunity? { store.opportunities.first { $0.id == opportunityID } }

    var body: some View {
        Group {
            if let opportunity {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack(alignment: .top) {
                            LedgerHeader(
                                eyebrow: "Research brief",
                                title: opportunity.title,
                                subtitle: "Earliest evidence \(opportunity.earliestPublishedAt.formatted(date: .abbreviated, time: .shortened))"
                            )
                            Spacer()
                            Button("Close") { dismiss() }.buttonStyle(SumiButtonStyle())
                        }
                        HStack {
                            StateLabel(text: opportunity.verification.rawValue, urgent: opportunity.verification != .confirmed)
                            StateLabel(text: opportunity.dataTruth.rawValue, urgent: opportunity.dataTruth.isAttentionRequired)
                            StateLabel(text: "Score \(opportunity.score.total)", urgent: opportunity.isHighPriority)
                            Text(opportunity.originalSource == nil ? "ORIGIN UNKNOWN" : "ORIGINAL SOURCE IDENTIFIED")
                                .font(SumiFont.meta(9))
                                .foregroundStyle(opportunity.originalSource == nil ? SumiColor.sealDeep : SumiColor.healthy)
                        }
                        Divider().overlay(SumiColor.ink)
                        Text(opportunity.brief).font(SumiFont.body(16))
                        ScoreLedger(score: opportunity.score)
                        DetailSection(title: "ARABIC COVERAGE GAP", content: opportunity.coverageExplanation)
                        DetailSection(title: "EGYPT & GULF RELEVANCE", content: opportunity.regionalExplanation)
                        SectionTitle("EVIDENCE TIMELINE")
                        ForEach(opportunity.items) { item in
                            Link(destination: item.url) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(item.title).font(SumiFont.body(14))
                                        Text("\(item.group.rawValue.uppercased()) · \(item.author) · \(item.country) · \(item.language)")
                                            .font(SumiFont.meta(9))
                                            .foregroundStyle(SumiColor.mutedInk)
                                    }
                                    Spacer()
                                    Text(item.publishedAt, style: .relative).font(SumiFont.meta(9))
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 8)
                            .overlay(alignment: .bottom) { Divider().overlay(SumiColor.rule) }
                        }
                        HStack {
                            Button("Save") { store.updateDisposition(.saved, id: opportunity.id) }
                            Button("Watch") { store.updateDisposition(.watched, id: opportunity.id) }
                            Button("Dismiss") {
                                store.updateDisposition(.dismissed, id: opportunity.id)
                                dismiss()
                            }
                            Button("Mute") {
                                store.updateDisposition(.muted, id: opportunity.id)
                                dismiss()
                            }
                        }
                        .buttonStyle(SumiButtonStyle())
                    }
                    .padding(30)
                }
            } else {
                Text("Opportunity unavailable").font(SumiFont.body())
            }
        }
        .frame(minWidth: 760, minHeight: 680)
        .background(SumiColor.paper)
    }
}

private struct ScoreLedger: View {
    let score: ScoreBreakdown
    var entries: [(String, Int)] {
        [
            ("Freshness", score.freshness), ("Source credibility", score.credibility),
            ("Cross-source momentum", score.momentum), ("Watched creator activity", score.creatorActivity),
            ("Arabic coverage gap", score.arabicCoverageGap), ("Regional relevance", score.regionalRelevance)
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(entries, id: \.0) { label, value in
                HStack {
                    Text(label).font(SumiFont.body())
                    Spacer()
                    Text("\(value)").font(SumiFont.display(18))
                }
                .padding(.vertical, 7)
                .overlay(alignment: .bottom) { Divider().overlay(SumiColor.rule) }
            }
        }
        .padding(14)
        .background(SumiColor.softPaper)
        .overlay(Rectangle().stroke(SumiColor.rule, lineWidth: 1))
    }
}

private struct DetailSection: View {
    let title: String
    let content: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionTitle(title)
            Text(content).font(SumiFont.body())
        }
    }
}

struct FirstRunView: View {
    @EnvironmentObject private var store: AppStore
    @State private var step = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("ZOID 99")
                .font(SumiFont.meta(11))
                .tracking(2)
                .foregroundStyle(SumiColor.sealDeep)
            Text(stepTitle)
                .font(SumiFont.display(38))
            Text(stepCopy)
                .font(SumiFont.body(16))
                .foregroundStyle(SumiColor.mutedInk)
            Divider().overlay(SumiColor.ink)
            stepContent
            Spacer()
            HStack {
                Text("STEP \(step + 1) OF 5")
                    .font(SumiFont.meta(10))
                    .tracking(1.3)
                Spacer()
                if step > 0 {
                    Button("Back") { step -= 1 }.buttonStyle(SumiButtonStyle())
                }
                Button(step == 4 ? "Enter Zoid 99" : "Continue") {
                    if step == 4 { store.completeSetup() } else { step += 1 }
                }
                .buttonStyle(SumiButtonStyle(primary: true))
            }
        }
        .padding(42)
        .frame(minWidth: 720, minHeight: 560)
        .background(SumiColor.paper)
    }

    private var stepTitle: String {
        ["Research before the noise", "Connect six source groups", "Choose your signal", "Allow useful alerts", "Confirm refresh & privacy"][step]
    }

    private var stepCopy: String {
        [
            "Detect early AI developments, verify their origin, and find the Arabic coverage gap without generating or publishing content.",
            "Credentials are optional during setup. Unconfigured sources remain clearly marked as setup required.",
            "Start with AI agents, Egypt, the Gulf, Arabic, and the creators that matter to your research.",
            "Only high-priority confirmed opportunities interrupt you. Lower-priority developments enter a digest.",
            "Local research persists across restarts for offline reading. Demo fixtures are explicitly labeled. Live credentials belong in Keychain, and an always-on service must be deployed separately."
        ][step]
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case 1:
            ProviderConnectionsLedger()
        case 2:
            Text("AI agents · Multimodal models · Egypt · Saudi Arabia · UAE · Oman · Arabic")
                .font(SumiFont.body(16))
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SumiColor.softPaper)
                .overlay(Rectangle().stroke(SumiColor.rule, lineWidth: 1))
        case 3:
            Button("Allow macOS notifications") { Task { await store.requestNotifications() } }
                .buttonStyle(SumiButtonStyle(urgent: true))
        case 4:
            VStack(alignment: .leading, spacing: 10) {
                Text("Refresh: every \(store.refreshMinutes) minutes")
                Text("Current evidence: \(store.dataTruth.rawValue)")
                Text("Live monitoring service: not deployed")
            }
            .font(SumiFont.body())
        default:
            Text("Original evidence and timestamps remain attached to every opportunity.")
                .font(SumiFont.body(16))
        }
    }
}
