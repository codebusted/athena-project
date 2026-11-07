import Foundation

public struct DailySession: Equatable, Sendable {
    public var date: String
    public var leetcodeProblemId: String?
    public var leetcodeTitle: String?
    public var leetcodeSlug: String?
    public var leetcodeDifficulty: String?
    public var leetcodeChallengeDate: String?
    public var leetcodeCompleted: Bool
    public var javaChallengeId: String?
    public var javaCompleted: Bool

    public var completedCount: Int { (leetcodeCompleted ? 1 : 0) + (javaCompleted ? 1 : 0) }
    public var isComplete: Bool { leetcodeCompleted && javaCompleted }

    public var leetcodeURL: URL? {
        guard let slug = leetcodeSlug else { return nil }
        return URL(string: "https://leetcode.com/problems/\(slug)/")
    }

    public init(
        date: String, leetcodeProblemId: String? = nil, leetcodeTitle: String? = nil, leetcodeSlug: String? = nil,
        leetcodeDifficulty: String? = nil, leetcodeChallengeDate: String? = nil, leetcodeCompleted: Bool = false,
        javaChallengeId: String? = nil, javaCompleted: Bool = false
    ) {
        self.date = date
        self.leetcodeProblemId = leetcodeProblemId
        self.leetcodeTitle = leetcodeTitle
        self.leetcodeSlug = leetcodeSlug
        self.leetcodeDifficulty = leetcodeDifficulty
        self.leetcodeChallengeDate = leetcodeChallengeDate
        self.leetcodeCompleted = leetcodeCompleted
        self.javaChallengeId = javaChallengeId
        self.javaCompleted = javaCompleted
    }
}

public struct Topic: Equatable, Hashable, Sendable {
    public var id: Int64
    public var name: String
    public var category: String
}

public struct ChallengeAttempt: Equatable, Sendable {
    public var id: Int64
    public var challengeId: String
    public var topicId: Int64
    public var exerciseType: ExerciseType?
    public var difficulty: Difficulty?
    public var userAnswer: String
    public var isCorrect: Bool?
    public var score: Double?
    public var mistakeCategory: MistakeCategory
    public var method: EvaluationMethod
    public var attemptedAt: Date
}

public enum TopicStatus: String, Sendable, CaseIterable {
    case new = "New"
    case needsPractice = "Needs practice"
    case improving = "Improving"
    case good = "Good"
    case strong = "Strong"
}

/// Derived from `challenge_attempts`; never written by the LLM.
public struct TopicProgress: Equatable, Sendable {
    public var topic: Topic
    public var attempts: Int
    public var correctAttempts: Int
    public var overallAccuracy: Double
    public var recentAccuracy: Double
    public var mastery: Double
    public var status: TopicStatus
    public var lastPracticedAt: Date?
    public var nextRevisionAt: Date?
    public var intervalDays: Int
    public var revisionCount: Int
    public var commonMistake: MistakeCategory?
}
