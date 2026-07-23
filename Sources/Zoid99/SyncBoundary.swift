import Foundation
import Security

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

struct ProductionResearchSync: ResearchSyncing {
    private let backend: BackendResearchSync?

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard
            let rawURL = environment["ZOID99_API_BASE_URL"],
            let baseURL = URL(string: rawURL),
            let token = environment["ZOID99_API_TOKEN"] ?? Self.keychainToken(),
            token.count >= 32
        else {
            backend = nil
            return
        }
        backend = BackendResearchSync(baseURL: baseURL, token: token)
    }

    private static func keychainToken() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "Zoid99Backend",
            kSecAttrAccount: "api-token",
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func synchronize() async -> [SourceSyncResult] {
        guard let backend else { return await NoopResearchSync().synchronize() }
        return await backend.synchronize()
    }
}
