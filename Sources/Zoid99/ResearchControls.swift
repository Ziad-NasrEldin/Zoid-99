import Foundation

enum RadarFreshness: String, CaseIterable, Identifiable, Sendable {
    case any = "Any time"
    case lastHour = "Last hour"
    case lastDay = "Last 24 hours"
    case lastThreeDays = "Last 3 days"
    case lastWeek = "Last 7 days"

    var id: String { rawValue }

    func includes(_ date: Date, now: Date) -> Bool {
        guard self != .any else { return true }
        let interval: TimeInterval = switch self {
        case .any: 0
        case .lastHour: 3_600
        case .lastDay: 24 * 3_600
        case .lastThreeDays: 3 * 24 * 3_600
        case .lastWeek: 7 * 24 * 3_600
        }
        return date >= now.addingTimeInterval(-interval)
    }
}

enum TopicResearchState: Equatable, Sendable {
    case prompt
    case results
    case noMatches
    case missingData
}

struct TopicSourceCoverage: Identifiable, Equatable, Sendable {
    var id: SourceGroup { group }
    let group: SourceGroup
    let matchingEvidenceCount: Int
    let state: ConnectionState
    let dataTruth: DataTruth
}

struct TopicResearchResult: Sendable {
    let query: String
    let state: TopicResearchState
    let evidence: [SourceItem]
    let opportunities: [Opportunity]
    let sourceCoverage: [TopicSourceCoverage]

    var stateMessage: String {
        switch state {
        case .prompt:
            "Enter a topic to search every collected source."
        case .results:
            "\(evidence.count) original evidence item\(evidence.count == 1 ? "" : "s") across \(Set(evidence.map(\.group)).count) source group\(Set(evidence.map(\.group)).count == 1 ? "" : "s")."
        case .noMatches:
            "No collected evidence matches this topic. This is zero results, not missing source data."
        case .missingData:
            "Topic research cannot run because no collected source evidence is available."
        }
    }
}

enum ResearchTextDirection: Equatable, Sendable {
    case leftToRight
    case rightToLeft

    static func resolve(languageCode: String? = nil, text: String) -> ResearchTextDirection {
        if let languageCode, languageCode.lowercased().hasPrefix("ar") {
            return .rightToLeft
        }
        return text.unicodeScalars.contains { scalar in
            (0x0600...0x06FF).contains(scalar.value)
                || (0x0750...0x077F).contains(scalar.value)
                || (0x08A0...0x08FF).contains(scalar.value)
        } ? .rightToLeft : .leftToRight
    }
}

enum WatchlistSupportLevel: String, Sendable {
    case providerQuery = "Provider query when connected"
    case collectedEvidence = "Collected evidence only"
    case unsupported = "Not supported by provider"
}

enum WatchlistValidationError: LocalizedError, Equatable {
    case empty
    case tooLong
    case invalidOfficialSourceURL
    case duplicate

    var errorDescription: String? {
        switch self {
        case .empty:
            "Enter a value before saving."
        case .tooLong:
            "Keep watchlist values at 500 characters or fewer."
        case .invalidOfficialSourceURL:
            "Official sources must use a complete https:// link."
        case .duplicate:
            "This value is already monitored in the selected watchlist."
        }
    }
}

enum WatchlistValidator {
    static func validatedValue(
        kind: WatchlistEntry.Kind,
        value: String,
        existing: [WatchlistEntry],
        excludingID: UUID? = nil
    ) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw WatchlistValidationError.empty }
        guard trimmed.count <= 500 else { throw WatchlistValidationError.tooLong }
        if kind == .officialSource {
            guard let url = URL(string: trimmed),
                  url.scheme?.lowercased() == "https",
                  url.host?.isEmpty == false else {
                throw WatchlistValidationError.invalidOfficialSourceURL
            }
        }
        guard !existing.contains(where: {
            $0.id != excludingID
                && $0.kind == kind
                && $0.value.compare(
                    trimmed,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) == .orderedSame
        }) else {
            throw WatchlistValidationError.duplicate
        }
        return trimmed
    }
}

struct WatchlistConnectorSupport: Identifiable, Equatable, Sendable {
    var id: SourceGroup { group }
    let group: SourceGroup
    let level: WatchlistSupportLevel
}

extension WatchlistEntry.Kind {
    var connectorSupport: [WatchlistConnectorSupport] {
        SourceGroup.allCases.map { group in
            WatchlistConnectorSupport(group: group, level: supportLevel(for: group))
        }
    }

    private func supportLevel(for group: SourceGroup) -> WatchlistSupportLevel {
        switch (self, group) {
        case (.creator, .youtube), (.creator, .instagram), (.creator, .x):
            .providerQuery
        case (.officialSource, .official):
            .providerQuery
        case (.company, .youtube), (.company, .googleTrends), (.company, .x):
            .providerQuery
        case (.keyword, .youtube), (.keyword, .googleTrends), (.keyword, .x),
             (.topic, .youtube), (.topic, .googleTrends), (.topic, .x):
            .providerQuery
        case (.country, .youtube), (.country, .googleTrends):
            .providerQuery
        case (.language, .youtube), (.language, .googleTrends), (.language, .x):
            .providerQuery
        case (.company, .comments), (.company, .official),
             (.keyword, .comments), (.keyword, .official),
             (.topic, .comments), (.topic, .official),
             (.country, .comments), (.country, .instagram), (.country, .official), (.country, .x),
             (.language, .comments), (.language, .instagram), (.language, .official):
            .collectedEvidence
        default:
            .unsupported
        }
    }
}
