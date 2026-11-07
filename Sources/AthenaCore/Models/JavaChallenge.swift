import Foundation

public enum Difficulty: String, Codable, CaseIterable, Sendable {
    case easy = "Easy"
    case medium = "Medium"
    case hard = "Hard"

    /// Lenient parse for LLM output and CLI input ("easy", "EASY", "Easy").
    public init?(loose: String) {
        guard let match = Difficulty.allCases.first(where: { $0.rawValue.lowercased() == loose.lowercased() }) else { return nil }
        self = match
    }
}

public enum ExerciseType: String, Codable, CaseIterable, Sendable {
    case predictOutput = "predict_output"
    case identifyBug = "identify_bug"
    case fixCode = "fix_code"
    case explainConcept = "explain_concept"
    case apiRecall = "api_recall"
    case completeCode = "complete_code"
    case smallCoding = "small_coding"

    public var label: String {
        switch self {
        case .predictOutput: "Predict the output"
        case .identifyBug: "Identify the bug"
        case .fixCode: "Fix the code"
        case .explainConcept: "Explain the concept"
        case .apiRecall: "API recall"
        case .completeCode: "Complete the code"
        case .smallCoding: "Small coding exercise"
        }
    }

    /// Short answers are graded deterministically against a reference; the rest need criteria-based grading.
    public var isDeterministic: Bool {
        self == .predictOutput || self == .apiRecall
    }

    public var expectsMultilineAnswer: Bool {
        switch self {
        case .fixCode, .completeCode, .smallCoding, .explainConcept, .identifyBug: true
        case .predictOutput, .apiRecall: false
        }
    }
}

public enum ChallengeSource: String, Codable, Sendable {
    case llm
    case bank
}

public struct JavaChallenge: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var topic: String
    public var difficulty: Difficulty
    public var type: ExerciseType
    public var question: String
    public var code: String?
    public var expectedAnswer: String
    /// Other answers that should also be accepted by deterministic grading (e.g. "[1, 2]" vs "[1,2]" is handled by
    /// normalisation; this is for genuinely different spellings such as "pollFirst()" vs "poll()").
    public var acceptableAnswers: [String]
    public var explanation: String
    public var evaluationCriteria: [String]
    public var source: ChallengeSource

    public init(
        id: String, topic: String, difficulty: Difficulty, type: ExerciseType, question: String, code: String? = nil,
        expectedAnswer: String, acceptableAnswers: [String] = [], explanation: String, evaluationCriteria: [String] = [],
        source: ChallengeSource = .bank
    ) {
        self.id = id
        self.topic = topic
        self.difficulty = difficulty
        self.type = type
        self.question = question
        self.code = code
        self.expectedAnswer = expectedAnswer
        self.acceptableAnswers = acceptableAnswers
        self.explanation = explanation
        self.evaluationCriteria = evaluationCriteria
        self.source = source
    }
}

/// What the scheduler asks for. The LLM only fills in the content.
public struct ExerciseRequest: Equatable, Sendable {
    public var topic: String
    public var category: String
    public var difficulty: Difficulty
    public var type: ExerciseType

    public init(topic: String, category: String, difficulty: Difficulty, type: ExerciseType) {
        self.topic = topic
        self.category = category
        self.difficulty = difficulty
        self.type = type
    }
}
