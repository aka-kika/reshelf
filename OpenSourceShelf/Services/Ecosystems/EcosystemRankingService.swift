import Foundation

struct EcosystemRankingInput {
    var repositoryCount: Int
    var relationshipCount: Int
    var averageConfidence: Double
    var averageRecommendationScore: Double
    var averagePersonalRelevance: Double
    var averageLocalFirstScore: Double
    var averageExperimentationPriority: Double
}

enum EcosystemRankingService {
    static func rank(_ input: EcosystemRankingInput) -> Double {
        let countScore = min(25, Double(input.repositoryCount) * 6)
        let densityScore = min(20, Double(input.relationshipCount) * 2.5)
        let confidenceScore = input.averageConfidence * 18
        let recommendationScore = min(14, input.averageRecommendationScore / 100 * 14)
        let relevanceScore = min(10, input.averagePersonalRelevance)
        let localFirstScore = min(7, input.averageLocalFirstScore * 0.7)
        let experimentScore = min(6, input.averageExperimentationPriority * 0.6)

        return min(100, countScore + densityScore + confidenceScore + recommendationScore + relevanceScore + localFirstScore + experimentScore)
    }

    static func confidence(repositoryCount: Int, averageConfidence: Double, relationshipCount: Int) -> Double {
        let countFactor = min(1, Double(repositoryCount) / 4)
        let densityFactor = min(1, Double(relationshipCount) / 8)
        return min(1, (averageConfidence * 0.55) + (countFactor * 0.25) + (densityFactor * 0.20))
    }
}
