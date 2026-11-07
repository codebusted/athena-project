import Foundation

public enum MistakeCategory: String, Codable, CaseIterable, Sendable {
    case none
    case conceptual
    case apiMisuse = "api_misuse"
    case syntax
    case edgeCase = "edge_case"
    case careless
    case incomplete

    public init(loose: String) {
        let key = loose.lowercased().replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "-", with: "_")
        self = MistakeCategory(rawValue: key) ?? .conceptual
    }

    public var label: String {
        switch self {
        case .none: "None"
        case .conceptual: "Conceptual"
        case .apiMisuse: "API misuse"
        case .syntax: "Syntax"
        case .edgeCase: "Edge case"
        case .careless: "Careless slip"
        case .incomplete: "Incomplete answer"
        }
    }
}

/// How a verdict was reached. Only verified methods feed learning scores.
public enum EvaluationMethod: String, Codable, Sendable {
    /// Compared against the challenge's reference answer by the app.
    case deterministic
    /// LLM judged each criterion and the app validated and aggregated the judgement.
    case criteria
    /// The user graded themselves after seeing the reference answer (used when the LLM is unavailable/invalid).
    case selfGraded = "self"
    /// No trustworthy verdict. Recorded for history, ignored for scoring.
    case unverified

    public var countsTowardProgress: Bool { self != .unverified }
}

public struct Evaluation: Equatable, Sendable {
    public var isCorrect: Bool?
    public var score: Double?
    public var mistakeCategory: MistakeCategory
    public var feedback: String
    public var correctAnswer: String
    public var explanation: String
    public var misunderstanding: String?
    public var method: EvaluationMethod

    public init(
        isCorrect: Bool?, score: Double?, mistakeCategory: MistakeCategory, feedback: String, correctAnswer: String,
        explanation: String, misunderstanding: String? = nil, method: EvaluationMethod
    ) {
        self.isCorrect = isCorrect
        self.score = score
        self.mistakeCategory = mistakeCategory
        self.feedback = feedback
        self.correctAnswer = correctAnswer
        self.explanation = explanation
        self.misunderstanding = misunderstanding
        self.method = method
    }
}
