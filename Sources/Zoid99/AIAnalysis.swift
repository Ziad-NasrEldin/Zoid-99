import Foundation

enum AIAnalysisStatus: String, Codable, Sendable {
    case notRequested
    case applied
    case unavailableFallback
    case invalidOutputFallback
    case budgetExceededFallback
}

struct AIAnalysisPolicy: Hashable, Sendable {
    let maxAttempts: Int
    let maxInputItems: Int
    let maxOutputCharacters: Int

    init(maxAttempts: Int = 2, maxInputItems: Int = 40, maxOutputCharacters: Int = 4_000) {
        self.maxAttempts = max(1, min(maxAttempts, 3))
        self.maxInputItems = max(1, min(maxInputItems, 100))
        self.maxOutputCharacters = max(200, min(maxOutputCharacters, 12_000))
    }
}

struct AIAnalysisSource: Codable, Hashable, Sendable {
    let sourceID: String
    let title: String
    let summary: String
    let language: String
    let country: String
}

struct AIAnalysisCluster: Codable, Hashable, Sendable {
    let clusterID: String
    let sources: [AIAnalysisSource]
}

struct AIAnalysisRequest: Codable, Hashable, Sendable {
    let schemaVersion: Int
    let instruction: String
    let clusters: [AIAnalysisCluster]
}

struct AIClusterInterpretation: Codable, Hashable, Sendable {
    let clusterID: String
    let conciseSummary: String
    let regionalInterpretation: String
    let citedSourceIDs: [String]
}

struct AIAnalysisResponse: Codable, Hashable, Sendable {
    let schemaVersion: Int
    let interpretations: [AIClusterInterpretation]
}

enum AIAnalysisProviderError: Error, Equatable {
    case unavailable
}

protocol AIAnalysisProvider: Sendable {
    func analyze(_ request: AIAnalysisRequest) async throws -> AIAnalysisResponse
}

struct UnavailableAIAnalysisProvider: AIAnalysisProvider {
    func analyze(_ request: AIAnalysisRequest) async throws -> AIAnalysisResponse {
        throw AIAnalysisProviderError.unavailable
    }
}

enum AIAnalysisValidator {
    static func validate(
        _ response: AIAnalysisResponse,
        request: AIAnalysisRequest,
        policy: AIAnalysisPolicy
    ) -> [AIClusterInterpretation]? {
        guard response.schemaVersion == 1 else { return nil }
        guard !request.clusters.isEmpty, !response.interpretations.isEmpty else { return nil }
        let requests = Dictionary(uniqueKeysWithValues: request.clusters.map { ($0.clusterID, $0) })
        var seen = Set<String>()
        var outputCharacters = 0

        for interpretation in response.interpretations {
            outputCharacters += interpretation.conciseSummary.count
            outputCharacters += interpretation.regionalInterpretation.count
            guard
                seen.insert(interpretation.clusterID).inserted,
                let cluster = requests[interpretation.clusterID],
                !interpretation.conciseSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                outputCharacters <= policy.maxOutputCharacters,
                !interpretation.citedSourceIDs.isEmpty
            else { return nil }

            let allowedSources = Set(cluster.sources.map(\.sourceID))
            guard Set(interpretation.citedSourceIDs).isSubset(of: allowedSources) else { return nil }
        }

        return response.interpretations
    }
}
