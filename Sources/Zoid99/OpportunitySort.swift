import Foundation

enum OpportunitySort: String, CaseIterable, Identifiable, Sendable {
    case totalScore
    case newest
    case highPriority
    case regionalRelevance
    case arabicCoverageGap

    static let storageKey = "liveRadar.opportunitySort"

    var id: Self { self }

    var title: String {
        switch self {
        case .totalScore: "Total Score"
        case .newest: "Newest"
        case .highPriority: "High Priority"
        case .regionalRelevance: "Regional Relevance"
        case .arabicCoverageGap: "Arabic Coverage Gap"
        }
    }

    func sorted(_ opportunities: [Opportunity]) -> [Opportunity] {
        opportunities.sorted(by: comesBefore)
    }

    private func comesBefore(_ left: Opportunity, _ right: Opportunity) -> Bool {
        switch self {
        case .totalScore:
            if left.score.total != right.score.total {
                return left.score.total > right.score.total
            }
        case .newest:
            let leftDate = latestEvidenceDate(for: left)
            let rightDate = latestEvidenceDate(for: right)
            if leftDate != rightDate {
                return leftDate > rightDate
            }
        case .highPriority:
            if left.isHighPriority != right.isHighPriority {
                return left.isHighPriority
            }
        case .regionalRelevance:
            if left.score.regionalRelevance != right.score.regionalRelevance {
                return left.score.regionalRelevance > right.score.regionalRelevance
            }
        case .arabicCoverageGap:
            if left.score.arabicCoverageGap != right.score.arabicCoverageGap {
                return left.score.arabicCoverageGap > right.score.arabicCoverageGap
            }
        }

        if self != .totalScore, left.score.total != right.score.total {
            return left.score.total > right.score.total
        }

        let leftDate = latestEvidenceDate(for: left)
        let rightDate = latestEvidenceDate(for: right)
        if leftDate != rightDate {
            return leftDate > rightDate
        }
        return left.id.uuidString < right.id.uuidString
    }

    private func latestEvidenceDate(for opportunity: Opportunity) -> Date {
        opportunity.items.map(\.publishedAt).max() ?? opportunity.earliestPublishedAt
    }
}
