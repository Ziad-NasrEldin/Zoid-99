import Foundation

struct SourceSyncResult: Sendable {
    let group: SourceGroup
    let collectedAt: Date
    let items: [SourceItem]
    let state: ConnectionState
    let dataTruth: DataTruth
    let evidence: String
}
protocol ResearchSyncing: Sendable {
    func synchronize() async -> [SourceSyncResult]
}

struct NoopResearchSync: ResearchSyncing {
    func synchronize() async -> [SourceSyncResult] {
        SourceGroup.allCases.map {
            SourceSyncResult(
                group: $0,
                collectedAt: .now,
                items: [],
                state: .setupRequired,
                dataTruth: .missing,
                evidence: "No live connector is configured."
            )
        }
    }
}
