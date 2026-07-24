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

                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(AppDestination.allCases) { destination in
                            Button {
                                selection = destination
                            } label: {
                                SidebarRow(destination: destination, selected: selection == destination)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selection == destination ? [.isSelected] : [])
                        }
                    }
                    .padding(10)
                }
                .background(SumiColor.softPaper)
                .accessibilityLabel("Sidebar")

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
        .task {
            await store.synchronizePendingDispositions()
        }
        .onChange(of: store.selectedDestination) { _, value in
            selection = value
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

enum OpportunityQuickAction: String, CaseIterable, Identifiable {
    case save
    case watch
    case dismiss
    case mute

    var id: Self { self }

    var disposition: OpportunityDisposition {
        switch self {
        case .save: .saved
        case .watch: .watched
        case .dismiss: .dismissed
        case .mute: .muted
        }
    }

    var symbolName: String {
        switch self {
        case .save: "bookmark"
        case .watch: "eye"
        case .dismiss: "xmark"
        case .mute: "speaker.slash"
        }
    }

    var selectedSymbolName: String {
        switch self {
        case .save: "bookmark.fill"
        case .watch: "eye.fill"
        case .dismiss: "xmark"
        case .mute: "speaker.slash.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .save: "Save opportunity"
        case .watch: "Watch opportunity"
        case .dismiss: "Dismiss opportunity"
        case .mute: "Mute opportunity"
        }
    }

    var helpText: String {
        switch self {
        case .save: "Save this opportunity"
        case .watch: "Watch this opportunity for updates"
        case .dismiss: "Dismiss this opportunity from Today"
        case .mute: "Mute this opportunity from Today"
        }
    }

    func isSelected(for disposition: OpportunityDisposition) -> Bool {
        self.disposition == disposition
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

    private var textDirection: LayoutDirection {
        ResearchTextDirection.resolve(
            languageCode: opportunity.originalSource?.language,
            text: "\(opportunity.title) \(opportunity.brief)"
        ) == .rightToLeft ? .rightToLeft : .leftToRight
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                store.selectedOpportunityID = opportunity.id
            } label: {
                rowContent
                    .padding(.trailing, 48)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "\(opportunity.title), \(opportunity.verification.rawValue), "
                    + "\(opportunity.items.count) sources"
            )
            .accessibilityHint("Open the evidence and opportunity actions")

            VStack(spacing: 4) {
                ForEach(OpportunityQuickAction.allCases) { action in
                    OpportunityQuickActionButton(
                        action: action,
                        selected: action.isSelected(for: opportunity.disposition)
                    ) {
                        store.updateDisposition(action.disposition, id: opportunity.id)
                    }
                }
            }
            .padding(.trailing, 2)
            .environment(\.layoutDirection, .leftToRight)
        }
        .overlay(alignment: .bottom) { Divider().overlay(SumiColor.rule) }
        .sheet(isPresented: Binding(
            get: { store.selectedOpportunityID == opportunity.id },
            set: { if !$0 { store.selectedOpportunityID = nil } }
        )) {
            OpportunityDetailView(opportunityID: opportunity.id)
        }
    }

    private var rowContent: some View {
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
                    .environment(\.layoutDirection, textDirection)
                    .frame(
                        maxWidth: .infinity,
                        alignment: textDirection == .rightToLeft ? .trailing : .leading
                    )
                Text(opportunity.brief)
                    .font(SumiFont.body())
                    .foregroundStyle(SumiColor.mutedInk)
                    .lineLimit(2)
                    .environment(\.layoutDirection, textDirection)
                    .frame(
                        maxWidth: .infinity,
                        alignment: textDirection == .rightToLeft ? .trailing : .leading
                    )
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
}

private struct OpportunityQuickActionButton: View {
    let action: OpportunityQuickAction
    let selected: Bool
    let perform: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: perform) {
            Image(systemName: selected ? action.selectedSymbolName : action.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 34, height: 34)
                .foregroundStyle(selected ? SumiColor.paper : SumiColor.ink)
                .background(selected ? SumiColor.ink : hovered ? SumiColor.mist : SumiColor.paper)
                .overlay(Rectangle().stroke(selected ? SumiColor.ink : SumiColor.rule, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(SumiPressStyle())
        .disabled(selected)
        .accessibilityLabel(action.accessibilityLabel)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .help(action.helpText)
        .onHover { hovered = $0 }
    }
}

struct RadarView: View {
    @EnvironmentObject private var store: AppStore
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LedgerHeader(
                eyebrow: "Six-source chronology",
                title: "Live Radar",
                subtitle: "Everything collected, with duplicates combined before ranking."
            )
            VStack(alignment: .leading, spacing: 10) {
                TextField("Search titles, evidence, authors, and topics", text: $store.searchText)
                    .sumiField()
                    .focused($searchFocused)
                    .accessibilityLabel("Search Live Radar evidence")
                HStack(spacing: 10) {
                    SumiSelect(
                        title: "Source",
                        selection: $store.radarSource,
                        options: [.init(value: nil, title: "All sources")]
                            + SourceGroup.allCases.map { .init(value: Optional($0), title: $0.rawValue) },
                        accessibilityLabel: "Filter by source",
                        width: 145
                    )
                    TextField("Topic", text: $store.radarTopic)
                        .sumiField()
                        .frame(minWidth: 130)
                        .accessibilityLabel("Filter by topic")
                    SumiSelect(
                        title: "Country",
                        selection: $store.radarCountry,
                        options: [.init(value: nil, title: "Any country")]
                            + store.radarCountries.map { .init(value: Optional($0), title: $0) },
                        accessibilityLabel: "Filter by country",
                        width: 135
                    )
                    SumiSelect(
                        title: "Language",
                        selection: $store.radarLanguage,
                        options: [.init(value: nil, title: "Any language")]
                            + store.radarLanguages.map { .init(value: Optional($0), title: $0) },
                        accessibilityLabel: "Filter by language",
                        width: 135
                    )
                }
                HStack(spacing: 10) {
                    SumiSelect(
                        title: "Freshness",
                        selection: $store.radarFreshness,
                        options: RadarFreshness.allCases.map { .init(value: $0, title: $0.rawValue) },
                        accessibilityLabel: "Filter by freshness",
                        width: 125
                    )
                    SumiSelect(
                        title: "Verification",
                        selection: $store.radarVerification,
                        options: [.init(value: nil, title: "Any state")]
                            + VerificationState.allCases.map { .init(value: Optional($0), title: $0.rawValue) },
                        accessibilityLabel: "Filter by verification",
                        width: 135
                    )
                    SumiSelect(
                        title: "Sort",
                        selection: Binding(
                            get: { store.radarSort },
                            set: { store.setRadarSort($0) }
                        ),
                        options: OpportunitySort.allCases.map { .init(value: $0, title: $0.title) },
                        accessibilityLabel: "Sort Live Radar opportunities",
                        width: 165
                    )
                    Button("Reset sort") { store.resetRadarSort() }
                        .buttonStyle(SumiButtonStyle())
                        .disabled(store.radarSort == .totalScore)
                        .accessibilityLabel("Reset sort to Total Score")
                    Spacer()
                    StateLabel(
                        text: "\(store.radarOpportunities.count) "
                            + (store.radarOpportunities.count == 1 ? "match" : "matches")
                    )
                    Button("Clear filters") { store.clearRadarFilters() }
                        .buttonStyle(SumiButtonStyle())
                }
            }
            Divider().overlay(SumiColor.ink)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if store.radarOpportunities.isEmpty {
                        ResearchEmptyState(
                            title: store.activeOpportunities.isEmpty
                                ? "Research data missing"
                                : "Zero matches",
                            message: store.activeOpportunities.isEmpty
                                ? "Connect or refresh a source before relying on Live Radar."
                                : "No collected evidence matches every selected filter."
                        )
                    } else {
                        ForEach(store.radarOpportunities) { OpportunityRow(opportunity: $0) }
                    }
                }
            }
        }
        .padding(30)
        .sumiPage()
        .onChange(of: store.searchFocusRequest) { _, _ in searchFocused = true }
    }
}

struct TopicsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var topicQuery = ""

    private var result: TopicResearchResult { store.topicResearch(query: topicQuery) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LedgerHeader(
                eyebrow: "Cross-source research",
                title: "Topics",
                subtitle: "Compare global evidence, creator coverage, and Arabic-market gaps."
            )
            HStack(spacing: 10) {
                TextField("Research a topic across every collected source", text: $topicQuery)
                    .sumiField()
                    .accessibilityLabel("Cross-source topic research query")
                    .onSubmit {
                        Task { await store.researchTopicAcrossConnectedSources(topicQuery) }
                    }
                Button(store.isResearchingTopic ? "Researching" : "Research connected sources") {
                    Task { await store.researchTopicAcrossConnectedSources(topicQuery) }
                }
                .buttonStyle(SumiButtonStyle())
                .disabled(
                    topicQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || store.isResearchingTopic
                )
                .accessibilityHint("Refresh every configured official provider and retain original evidence")
                StateLabel(text: result.stateMessage)
                if !topicQuery.isEmpty {
                    Button("Clear") { topicQuery = "" }
                        .buttonStyle(SumiButtonStyle())
                }
            }
            Divider().overlay(SumiColor.ink)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    TopicCoverageLedger(coverage: result.sourceCoverage)
                    switch result.state {
                    case .prompt:
                        ResearchEmptyState(
                            title: "Research across six sources",
                            message: result.stateMessage
                        )
                    case .missingData:
                        ResearchEmptyState(title: "Research data missing", message: result.stateMessage)
                    case .noMatches:
                        ResearchEmptyState(title: "Zero matches", message: result.stateMessage)
                    case .results:
                        ForEach(result.evidence) { item in
                            TopicEvidenceRow(item: item)
                        }
                        if !result.opportunities.isEmpty {
                            SectionTitle("RELATED OPPORTUNITIES")
                            ForEach(result.opportunities) { OpportunityRow(opportunity: $0) }
                        }
                    }
                }
            }
        }
        .padding(30)
        .sumiPage()
    }
}

private struct ResearchEmptyState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(SumiFont.display(21))
            Text(message)
                .font(SumiFont.body())
                .foregroundStyle(SumiColor.mutedInk)
        }
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
        .padding(20)
        .background(SumiColor.softPaper)
        .overlay(Rectangle().stroke(SumiColor.rule, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

private struct TopicCoverageLedger: View {
    let coverage: [TopicSourceCoverage]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("SOURCE COVERAGE")
            HStack(spacing: 8) {
                ForEach(coverage) { source in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(source.group.rawValue.uppercased())
                            .font(SumiFont.meta(8))
                            .lineLimit(1)
                        Text("\(source.matchingEvidenceCount) evidence")
                            .font(SumiFont.body(11))
                        Text(source.dataTruth.rawValue)
                            .font(SumiFont.meta(8))
                            .foregroundStyle(
                                source.dataTruth.isAttentionRequired ? SumiColor.seal : SumiColor.mutedInk
                            )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(SumiColor.softPaper)
                    .overlay(Rectangle().stroke(SumiColor.rule, lineWidth: 1))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private struct TopicEvidenceRow: View {
    let item: SourceItem

    private var direction: LayoutDirection {
        ResearchTextDirection.resolve(languageCode: item.language, text: item.title) == .rightToLeft
            ? .rightToLeft
            : .leftToRight
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Rectangle().fill(item.isOriginalSource ? SumiColor.seal : SumiColor.ink).frame(width: 2)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    StateLabel(text: item.group.rawValue)
                    if item.isOriginalSource { StateLabel(text: "Original evidence", urgent: true) }
                    Spacer()
                    Text(item.publishedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(SumiFont.meta(9))
                        .foregroundStyle(SumiColor.mutedInk)
                }
                Link(destination: item.url) {
                    Text(item.title)
                        .font(SumiFont.display(18))
                        .environment(\.layoutDirection, direction)
                        .frame(
                            maxWidth: .infinity,
                            alignment: direction == .rightToLeft ? .trailing : .leading
                        )
                }
                .foregroundStyle(SumiColor.ink)
                Text(item.summary)
                    .font(SumiFont.body())
                    .foregroundStyle(SumiColor.mutedInk)
                    .environment(\.layoutDirection, direction)
                    .frame(
                        maxWidth: .infinity,
                        alignment: direction == .rightToLeft ? .trailing : .leading
                    )
                Text("\(item.author) - \(item.country) - \(item.language)")
                    .font(SumiFont.meta(9))
                    .foregroundStyle(SumiColor.mutedInk)
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Divider().overlay(SumiColor.rule) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(item.isOriginalSource ? "Original evidence" : "Supporting evidence"), "
                + "\(item.group.rawValue), \(item.title)"
        )
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
    @State private var selectedKind: WatchlistEntry.Kind?
    @State private var editingEntry: WatchlistEntry?
    @State private var pendingRemoval: WatchlistEntry?

    private var visibleEntries: [WatchlistEntry] {
        store.watchlist.filter { selectedKind == nil || $0.kind == selectedKind }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LedgerHeader(
                eyebrow: "Monitoring scope",
                title: "Watchlists",
                subtitle: "Creators, official sources, companies, keywords, topics, countries, and languages."
            )
            HStack(spacing: 10) {
                SumiSelect(
                    title: "Type",
                    selection: $kind,
                    options: WatchlistEntry.Kind.allCases.map { .init(value: $0, title: $0.rawValue) },
                    accessibilityLabel: "Watchlist type",
                    width: 150
                )
                TextField(
                    kind == .officialSource
                        ? "https://source.example/feed"
                        : "Add \(kind.rawValue.lowercased())",
                    text: $newValue
                )
                    .sumiField()
                Button("Add") {
                    if store.addWatchlist(kind: kind, value: newValue) { newValue = "" }
                }
                .buttonStyle(SumiButtonStyle(primary: true))
                .keyboardShortcut(.return, modifiers: [])
                .disabled(newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let error = store.watchlistError {
                Text(error)
                    .font(SumiFont.body(13))
                    .foregroundStyle(SumiColor.seal)
                    .accessibilityLabel("Watchlist error: \(error)")
            }
            Divider().overlay(SumiColor.ink)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    WatchlistFilterButton(
                        title: "All",
                        count: store.watchlist.count,
                        selected: selectedKind == nil
                    ) { selectedKind = nil }
                    ForEach(WatchlistEntry.Kind.allCases, id: \.self) { entryKind in
                        WatchlistFilterButton(
                            title: entryKind.rawValue,
                            count: store.watchlist.filter { $0.kind == entryKind }.count,
                            selected: selectedKind == entryKind
                        ) { selectedKind = entryKind }
                    }
                }
            }

            if store.watchlist.isEmpty {
                ResearchEmptyState(
                    title: "No monitoring watchlists",
                    message: "Add the first creator, source, company, keyword, topic, country, or language above."
                )
            } else if visibleEntries.isEmpty {
                ResearchEmptyState(
                    title: "No \(selectedKind?.rawValue.lowercased() ?? "matching") entries",
                    message: "This watchlist category is intentionally empty."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleEntries) { entry in
                            WatchlistLedgerRow(
                                entry: entry,
                                edit: { editingEntry = entry },
                                remove: { pendingRemoval = entry },
                                priorityChanged: {
                                    store.setWatchlistPriority(id: entry.id, highPriority: $0)
                                }
                            )
                        }
                    }
                }
            }

            HStack {
                StateLabel(
                    text: store.watchlistSyncState,
                    urgent: store.watchlistSyncState.contains("pending")
                )
                Spacer()
                Text("\(visibleEntries.count) SHOWN / \(store.watchlist.count) TOTAL")
                    .font(SumiFont.meta(9))
                    .tracking(1)
                    .foregroundStyle(SumiColor.mutedInk)
            }
        }
        .padding(30)
        .sumiPage()
        .sheet(item: $editingEntry) { entry in
            WatchlistEditor(entry: entry).environmentObject(store)
        }
        .sheet(item: $pendingRemoval) { entry in
            SumiConfirmationSheet(
                title: "Remove watchlist entry?",
                message: "\"\(entry.value)\" will stop being monitored.",
                confirmTitle: "Remove",
                cancel: { pendingRemoval = nil },
                confirm: {
                    store.removeWatchlist(id: entry.id)
                    pendingRemoval = nil
                }
            )
        }
    }
}

private struct WatchlistFilterButton: View {
    let title: String
    let count: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(title.uppercased()) \(count)")
                .font(SumiFont.meta(9))
                .tracking(0.7)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .foregroundStyle(selected ? SumiColor.paper : SumiColor.ink)
                .background(selected ? SumiColor.ink : SumiColor.paper)
                .overlay(Rectangle().stroke(SumiColor.ink, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count) entries")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private struct WatchlistLedgerRow: View {
    let entry: WatchlistEntry
    let edit: () -> Void
    let remove: () -> Void
    let priorityChanged: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Rectangle()
                .fill(entry.highPriority ? SumiColor.seal : SumiColor.ink)
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(entry.kind.rawValue.uppercased())
                        .font(SumiFont.meta(9))
                        .tracking(1)
                    if entry.highPriority { StateLabel(text: "High priority", urgent: true) }
                }
                Text(entry.value)
                    .font(SumiFont.body(16))
                    .textSelection(.enabled)
                ForEach(entry.kind.connectorSupport) { support in
                    Text("\(support.group.rawValue.uppercased()): \(support.level.rawValue)")
                        .font(SumiFont.meta(8))
                        .tracking(0.4)
                        .foregroundStyle(
                            support.level == .unsupported ? SumiColor.seal : SumiColor.mutedInk
                        )
                }
            }
            Spacer()
            Toggle(
                "High priority",
                isOn: Binding(get: { entry.highPriority }, set: priorityChanged)
            )
            .toggleStyle(SumiCheckboxStyle())
            .accessibilityLabel("High priority for \(entry.value)")
            Button("Edit", action: edit)
                .buttonStyle(SumiButtonStyle())
                .accessibilityLabel("Edit \(entry.kind.rawValue) \(entry.value)")
            Button("Remove", action: remove)
                .buttonStyle(SumiButtonStyle(urgent: true))
                .accessibilityLabel("Remove \(entry.kind.rawValue) \(entry.value)")
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) { Divider().overlay(SumiColor.rule) }
        .accessibilityElement(children: .contain)
    }
}

private struct WatchlistEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    let entry: WatchlistEntry
    @State private var kind: WatchlistEntry.Kind
    @State private var value: String
    @State private var highPriority: Bool

    init(entry: WatchlistEntry) {
        self.entry = entry
        _kind = State(initialValue: entry.kind)
        _value = State(initialValue: entry.value)
        _highPriority = State(initialValue: entry.highPriority)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LedgerHeader(
                eyebrow: "Monitoring scope",
                title: "Edit watchlist",
                subtitle: "Changes save locally first and synchronize through the private backend."
            )
            Divider().overlay(SumiColor.ink)
            SumiSelect(
                title: "Type",
                selection: $kind,
                options: WatchlistEntry.Kind.allCases.map { .init(value: $0, title: $0.rawValue) },
                accessibilityLabel: "Watchlist type",
                width: 220
            )
            TextField("Watchlist value", text: $value)
                .sumiField()
            Toggle("High priority", isOn: $highPriority).toggleStyle(SumiCheckboxStyle())
            if let error = store.watchlistError {
                Text(error).font(SumiFont.body(13)).foregroundStyle(SumiColor.seal)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SumiButtonStyle())
                Button("Save changes") {
                    if store.updateWatchlist(
                        id: entry.id,
                        kind: kind,
                        value: value,
                        highPriority: highPriority
                    ) {
                        dismiss()
                    }
                }
                .buttonStyle(SumiButtonStyle(primary: true))
            }
        }
        .padding(28)
        .frame(width: 540)
        .sumiPage()
        .onAppear { store.watchlistError = nil }
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
                StateLabel(
                    text: store.notificationPermission.rawValue,
                    urgent: store.notificationPermission != .authorized
                )
                Button(
                    store.notificationPermission == .notDetermined
                        ? "Allow notifications"
                        : "Check permission again"
                ) {
                    Task { await store.requestNotifications() }
                }
                    .buttonStyle(SumiButtonStyle(primary: true))
                Button("Send native test") { Task { await store.sendImmediateDemoNotification() } }
                    .buttonStyle(SumiButtonStyle(urgent: true))
                    .disabled(!store.notificationsEnabled)
            }
            Divider().overlay(SumiColor.ink)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.notifications) { record in
                        Button {
                            store.openNotificationDeepLink(
                                URL(string: "zoid99://opportunity/\(record.opportunityID.uuidString)")!
                            )
                        } label: {
                            HStack(alignment: .top, spacing: 14) {
                                StateLabel(text: record.delivery.rawValue, urgent: record.delivery == .immediate)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(record.title).font(SumiFont.body(15))
                                    HStack {
                                        StateLabel(
                                            text: record.deliveryState.rawValue,
                                            urgent: record.deliveryState == .failed
                                        )
                                        Text(record.statusDetail)
                                        if let scheduledAt = record.scheduledAt {
                                            Text("·")
                                            Text(scheduledAt, style: .relative)
                                        }
                                    }
                                        .font(SumiFont.meta(9))
                                        .foregroundStyle(SumiColor.mutedInk)
                                }
                                Spacer()
                                Text(record.isRead ? "Opened" : "Open detail")
                                    .font(SumiFont.meta(9))
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(record.isRead)
                        .accessibilityHint("Open notification opportunity detail")
                        .padding(.vertical, 12)
                        .overlay(alignment: .bottom) { Divider().overlay(SumiColor.rule) }
                    }
                }
            }
        }
        .padding(30)
        .sumiPage()
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var discordWebhook = ""
    @State private var confirmingDiscordRemoval = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                LedgerHeader(
                    eyebrow: "Operational truth",
                    title: "Sources & Settings",
                    subtitle: "Connection health, evidence, repair actions, refresh, and privacy."
                )
                SectionTitle("ACCESSIBILITY & KEYBOARD")
                HStack {
                    StateLabel(text: reduceMotion ? "Reduce Motion on" : "Reduce Motion off")
                    Text(
                        reduceMotion
                            ? "Spatial movement and press scaling are disabled; written state changes remain immediate."
                            : "Motion is restrained and brief. Turn on Reduce Motion in macOS to remove spatial movement."
                    )
                    .font(SumiFont.body())
                    .foregroundStyle(SumiColor.mutedInk)
                }
                Text("Command 1-7 opens each section. Command F focuses Live Radar search. Command R refreshes research.")
                    .font(SumiFont.body())
                    .foregroundStyle(SumiColor.mutedInk)
                    .accessibilityLabel(
                        "Keyboard shortcuts: Command 1 through 7 open sections, "
                            + "Command F focuses search, and Command R refreshes research."
                    )
                SectionTitle("NOTIFICATIONS")
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Toggle(
                            "Enable native alerts and digests",
                            isOn: Binding(
                                get: { store.notificationsEnabled },
                                set: store.setNotificationsEnabled
                            )
                        )
                        Spacer()
                        StateLabel(
                            text: store.notificationPermission.rawValue,
                            urgent: store.notificationPermission != .authorized
                        )
                    }
                    if store.notificationPermission == .notDetermined {
                        Button("Allow macOS notifications") {
                            Task { await store.requestNotifications() }
                        }
                        .buttonStyle(SumiButtonStyle(primary: true))
                    } else if store.notificationPermission == .denied {
                        Text("macOS is blocking delivery. Open System Settings > Notifications > Zoid 99 to allow it, then check permission again.")
                            .font(SumiFont.body())
                            .foregroundStyle(SumiColor.sealDeep)
                        Button("Check permission again") {
                            Task { await store.requestNotifications() }
                        }
                        .buttonStyle(SumiButtonStyle())
                    }
                    Divider().overlay(SumiColor.rule)
                    Toggle(
                        "Quiet hours",
                        isOn: Binding(
                            get: { store.quietHoursEnabled },
                            set: store.setQuietHoursEnabled
                        )
                    )
                    HStack {
                        SumiStepper(
                            title: "Start \(hourLabel(store.quietStartHour))",
                            decrement: { store.setQuietStartHour(max(0, store.quietStartHour - 1)) },
                            increment: { store.setQuietStartHour(min(23, store.quietStartHour + 1)) }
                        )
                        SumiStepper(
                            title: "End \(hourLabel(store.quietEndHour))",
                            decrement: { store.setQuietEndHour(max(0, store.quietEndHour - 1)) },
                            increment: { store.setQuietEndHour(min(23, store.quietEndHour + 1)) }
                        )
                        SumiStepper(
                            title: "Digest \(hourLabel(store.digestHour))",
                            decrement: { store.setDigestHour(max(0, store.digestHour - 1)) },
                            increment: { store.setDigestHour(min(23, store.digestHour + 1)) }
                        )
                    }
                    .disabled(!store.notificationsEnabled)
                    Text("Confirmed high-priority opportunities alert immediately outside quiet hours. Lower-priority opportunities are grouped into the next daily digest.")
                        .font(SumiFont.body())
                        .foregroundStyle(SumiColor.mutedInk)
                }
                .padding(16)
                .background(SumiColor.softPaper)
                .overlay(Rectangle().stroke(SumiColor.rule, lineWidth: 1))
                SectionTitle("DISCORD CHANNEL")
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Toggle(
                            "Enable Discord delivery",
                            isOn: Binding(
                                get: { store.discordEnabled },
                                set: store.setDiscordEnabled
                            )
                        )
                        .disabled(!store.discordConfigured)
                        Spacer()
                        StateLabel(
                            text: store.discordStatus.label,
                            urgent: {
                                if case .failed = store.discordStatus { return true }
                                return !store.discordConfigured
                            }()
                        )
                    }
                    Text(DiscordWebhookValidator.redactedDescription(configured: store.discordConfigured))
                        .font(SumiFont.body())
                        .foregroundStyle(SumiColor.mutedInk)
                    SecureField(
                        store.discordConfigured
                            ? "Paste a replacement Discord webhook"
                            : "Paste a Discord webhook",
                        text: $discordWebhook
                    )
                    .sumiField()
                    .textContentType(.password)
                    HStack {
                        Button(store.discordConfigured ? "Replace & validate" : "Save & validate") {
                            let submitted = discordWebhook
                            discordWebhook = ""
                            Task { await store.configureDiscordWebhook(submitted) }
                        }
                        .buttonStyle(SumiButtonStyle(primary: true))
                        .disabled(discordWebhook.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Send safe test") {
                            Task { await store.sendDiscordTest() }
                        }
                        .buttonStyle(SumiButtonStyle())
                        .disabled(!store.discordConfigured)
                        Button("Remove") {
                            discordWebhook = ""
                            confirmingDiscordRemoval = true
                        }
                        .buttonStyle(SumiButtonStyle(urgent: true))
                        .disabled(!store.discordConfigured)
                    }
                    Divider().overlay(SumiColor.rule)
                    Toggle(
                        "High-priority opportunities",
                        isOn: Binding(
                            get: { store.discordHighPriorityEnabled },
                            set: store.setDiscordHighPriorityEnabled
                        )
                    )
                    .disabled(!store.discordEnabled)
                    Text("Discord receives only new, confirmed high-priority research opportunities. Messages include the title, score, source, reason, and a public HTTPS source link when available. Credentials, diagnostics, and browsing history are never included.")
                        .font(SumiFont.body())
                        .foregroundStyle(SumiColor.mutedInk)
                    Text("Delivery is direct from this Mac. Rate-limit retries are capped at three attempts and 30 seconds. Alerts are recorded locally to prevent repeats after refresh or relaunch.")
                        .font(SumiFont.body())
                        .foregroundStyle(SumiColor.mutedInk)
                }
                .padding(16)
                .background(SumiColor.softPaper)
                .overlay(Rectangle().stroke(SumiColor.rule, lineWidth: 1))
                Divider().overlay(SumiColor.ink)
                SectionTitle("EXTERNAL PROVIDER CONNECTIONS")
                ProviderConnectionsLedger()
                SectionTitle("SOURCE HEALTH")
                SourceHealthLedger(compact: false)
                SectionTitle("REFRESH & PRIVACY")
                VStack(alignment: .leading, spacing: 14) {
                    SumiStepper(
                        title: "Refresh every \(store.refreshMinutes) minutes",
                        decrement: { store.setRefreshMinutes(max(5, store.refreshMinutes - 5)) },
                        increment: { store.setRefreshMinutes(min(60, store.refreshMinutes + 5)) }
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
        .task { await store.refreshDiscordConfigurationStatus() }
        .sheet(isPresented: $confirmingDiscordRemoval) {
            SumiConfirmationSheet(
                title: "Remove Discord webhook?",
                message: "This removes the webhook from macOS Keychain and disables Discord delivery. Native macOS notifications are unchanged.",
                confirmTitle: "Remove webhook",
                cancel: { confirmingDiscordRemoval = false },
                confirm: {
                    confirmingDiscordRemoval = false
                    Task { await store.removeDiscordWebhook() }
                }
            )
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
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
                        .sumiField()
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
                            StateLabel(text: opportunity.disposition.rawValue.uppercased())
                            Text(opportunity.originalSource == nil ? "ORIGIN UNKNOWN" : "ORIGINAL SOURCE IDENTIFIED")
                                .font(SumiFont.meta(9))
                                .foregroundStyle(opportunity.originalSource == nil ? SumiColor.sealDeep : SumiColor.healthy)
                        }
                        Divider().overlay(SumiColor.ink)
                        Text(opportunity.brief)
                            .font(SumiFont.body(16))
                            .environment(
                                \.layoutDirection,
                                ResearchTextDirection.resolve(
                                    languageCode: opportunity.originalSource?.language,
                                    text: opportunity.brief
                                ) == .rightToLeft ? .rightToLeft : .leftToRight
                            )
                        ScoreLedger(score: opportunity.score)
                        DetailSection(title: "ARABIC COVERAGE GAP", content: opportunity.coverageExplanation)
                        DetailSection(title: "EGYPT & GULF RELEVANCE", content: opportunity.regionalExplanation)
                        SectionTitle("EVIDENCE TIMELINE")
                        ForEach(opportunity.items) { item in
                            Link(destination: item.url) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(item.title)
                                            .font(SumiFont.body(14))
                                            .environment(
                                                \.layoutDirection,
                                                ResearchTextDirection.resolve(
                                                    languageCode: item.language,
                                                    text: item.title
                                                ) == .rightToLeft ? .rightToLeft : .leftToRight
                                            )
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
                                .accessibilityLabel("Save opportunity")
                            Button("Watch") { store.updateDisposition(.watched, id: opportunity.id) }
                                .accessibilityLabel("Watch opportunity")
                            Button("Dismiss") {
                                store.updateDisposition(.dismissed, id: opportunity.id)
                                dismiss()
                            }
                            .accessibilityLabel("Dismiss opportunity")
                            Button("Mute") {
                                store.updateDisposition(.muted, id: opportunity.id)
                                dismiss()
                            }
                            .accessibilityLabel("Mute opportunity")
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
