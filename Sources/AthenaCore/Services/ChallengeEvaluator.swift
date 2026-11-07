import Foundation

/// Hybrid grading. The app decides correctness; the LLM only supplies per-criterion judgements
/// and explanations, and those are validated before they can affect learning scores.
public struct ChallengeEvaluator: Sendable {
    /// Fraction of criteria that must be met for an open-ended answer to count as correct.
    public static let passThreshold = 0.75

    private let ollama: OllamaService?

    public init(ollama: OllamaService?) { self.ollama = ollama }

    public func evaluate(_ challenge: JavaChallenge, answer rawAnswer: String) async -> Evaluation {
        let answer = rawAnswer.trimmingCharacters(in: .whitespacesAndNewlines)

        if challenge.type.isDeterministic || (challenge.type == .completeCode && Self.matchesReference(answer, challenge)) {
            return await deterministic(challenge, answer: answer)
        }
        if answer.count < 3 {
            return Evaluation(
                isCorrect: false, score: 0, mistakeCategory: .incomplete, feedback: "No real attempt was submitted.",
                correctAnswer: challenge.expectedAnswer, explanation: challenge.explanation, method: .deterministic)
        }
        return await criteriaBased(challenge, answer: answer)
    }

    // MARK: Deterministic

    private func deterministic(_ challenge: JavaChallenge, answer: String) async -> Evaluation {
        let correct = Self.matchesReference(answer, challenge)
        if correct {
            return Evaluation(
                isCorrect: true, score: 1, mistakeCategory: .none, feedback: "Correct.",
                correctAnswer: challenge.expectedAnswer, explanation: challenge.explanation, method: .deterministic)
        }
        // Correctness is settled; ask the model only to diagnose the misunderstanding.
        let diagnosis = await diagnose(challenge, answer: answer)
        let category = Self.looksCareless(answer, challenge) ? .careless : (diagnosis?.category ?? .conceptual)
        return Evaluation(
            isCorrect: false, score: 0, mistakeCategory: category,
            feedback: answer.isEmpty ? "No answer submitted." : "Not quite.",
            correctAnswer: challenge.expectedAnswer, explanation: challenge.explanation,
            misunderstanding: diagnosis?.misunderstanding, method: .deterministic)
    }

    public static func matchesReference(_ answer: String, _ challenge: JavaChallenge) -> Bool {
        let references = [challenge.expectedAnswer] + challenge.acceptableAnswers
        switch challenge.type {
        case .predictOutput:
            let given = normalizeOutput(answer)
            return references.contains { normalizeOutput($0) == given }
        case .apiRecall, .completeCode:
            return references.contains { callMatches(answer, reference: $0) }
        default:
            return false
        }
    }

    /// Output comparison ignores whitespace layout (newlines vs spaces), surrounding quotes and a trailing period.
    static func normalizeOutput(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count >= 2, t.first == "\"", t.last == "\"" { t = String(t.dropFirst().dropLast()) }
        if t.hasSuffix(".") && !t.hasSuffix("..") { t = String(t.dropLast()) }
        return t.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Compares code-ish answers. For bare method names ("getOrDefault") the receiver and arguments are ignored,
    /// so "map.getOrDefault(k, 0)" matches. Otherwise whitespace, a trailing ';' and a leading "x =" are ignored.
    static func callMatches(_ answer: String, reference: String) -> Bool {
        func squash(_ s: String) -> String {
            var t = s.filter { !$0.isWhitespace }.lowercased()
            while t.hasSuffix(";") { t.removeLast() }
            if let eq = t.range(of: "=new") { t = String(t[t.index(after: eq.lowerBound)...]) }
            return t
        }
        func stripCall(_ s: String) -> String {
            guard s.hasSuffix(")"), let paren = s.firstIndex(of: "(") else { return s }
            return String(s[..<paren])
        }
        let given = squash(answer)
        let ref = squash(reference)
        if given == ref { return true }
        let isBareName = reference.range(of: #"^[A-Za-z_][A-Za-z0-9_.]*(\(\))?$"#, options: .regularExpression) != nil
        guard isBareName else { return false }
        let refName = stripCall(ref)
        let givenName = stripCall(given)
        return givenName == refName || givenName.hasSuffix("." + refName)
    }

    /// Same tokens, different punctuation/case → probably a slip rather than a misconception.
    static func looksCareless(_ answer: String, _ challenge: JavaChallenge) -> Bool {
        func letters(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        let given = letters(answer)
        return !given.isEmpty && ([challenge.expectedAnswer] + challenge.acceptableAnswers).contains { letters($0) == given }
    }

    private struct Diagnosis: Decodable {
        let misunderstanding: String
        let mistakeCategory: String
        var category: MistakeCategory { MistakeCategory(loose: mistakeCategory) }
    }

    private func diagnose(_ challenge: JavaChallenge, answer: String) async -> (misunderstanding: String, category: MistakeCategory)? {
        guard let ollama, !answer.isEmpty else { return nil }
        let prompt = """
            A learner answered a Java question incorrectly. The reference answer is verified correct.
            Topic: \(challenge.topic)
            Question: \(challenge.question)
            \(challenge.code.map { "Code:\n\($0)" } ?? "")
            Correct answer: \(challenge.expectedAnswer)
            Learner's answer: \(answer)

            In one or two sentences, state the most likely misunderstanding behind the learner's answer.
            Classify it as one of: conceptual, api_misuse, syntax, edge_case, careless.
            """
        guard let result = try? await ollama.chatJSON(
            system: Prompts.evaluatorSystem, user: prompt, schema: Prompts.diagnosisSchema, temperature: 0.2,
            as: Diagnosis.self),
            !result.misunderstanding.trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }
        let category = result.category == .none ? MistakeCategory.conceptual : result.category
        return (result.misunderstanding, category)
    }

    // MARK: Criteria-based (LLM judgement, app-side aggregation)

    struct CriteriaJudgement: Decodable {
        struct Item: Decodable { let index: Int; let met: Bool; let note: String? }
        let criteria: [Item]
        let isCorrect: Bool
        let mistakeCategory: String
        let feedback: String
        let misunderstanding: String?
    }

    private func criteriaBased(_ challenge: JavaChallenge, answer: String) async -> Evaluation {
        let criteria = challenge.evaluationCriteria
        guard let ollama, !criteria.isEmpty else { return unverified(challenge, reason: "The local model is unavailable.") }

        let prompt = """
            Grade a learner's answer to a Java interview exercise against each criterion independently.
            Be strict: a criterion is met only if the answer clearly satisfies it. Ignore style.

            Topic: \(challenge.topic)
            Exercise type: \(challenge.type.label)
            Question: \(challenge.question)
            \(challenge.code.map { "Code:\n\($0)" } ?? "")
            Reference answer: \(challenge.expectedAnswer)

            Criteria (0-indexed):
            \(criteria.enumerated().map { "\($0.offset). \($0.element)" }.joined(separator: "\n"))

            Learner's answer:
            \(answer)

            Return one entry per criterion with its index and whether it is met.
            Set isCorrect true only if the answer would be accepted in an interview.
            mistakeCategory: none if correct, otherwise one of conceptual, api_misuse, syntax, edge_case, careless, incomplete.
            feedback: one or two sentences addressed to the learner.
            misunderstanding: what the learner got wrong, or empty if correct.
            """

        for _ in 0..<2 {  // one retry on invalid output
            guard let judgement = try? await ollama.chatJSON(
                system: Prompts.evaluatorSystem, user: prompt, schema: Prompts.criteriaSchema, temperature: 0.1,
                as: CriteriaJudgement.self)
            else { continue }
            if let evaluation = Self.validate(judgement, for: challenge) { return evaluation }
        }
        return unverified(challenge, reason: "The model's grading did not pass validation.")
    }

    /// Accepts an LLM judgement only if it covers every criterion exactly once and its overall verdict agrees
    /// with the criteria. The final verdict is computed here, not taken from the model.
    static func validate(_ judgement: CriteriaJudgement, for challenge: JavaChallenge) -> Evaluation? {
        let n = challenge.evaluationCriteria.count
        let indices = judgement.criteria.map(\.index)
        guard n > 0, indices.count == n, Set(indices) == Set(0..<n) else { return nil }

        let score = Double(judgement.criteria.filter(\.met).count) / Double(n)
        let passes = score >= passThreshold
        guard passes == judgement.isCorrect else { return nil }

        var category = MistakeCategory(loose: judgement.mistakeCategory)
        if passes { category = .none } else if category == .none { category = .conceptual }

        let missed = judgement.criteria.filter { !$0.met }.sorted { $0.index < $1.index }
            .map { "Missed: \(challenge.evaluationCriteria[$0.index])" }
        let misunderstanding = judgement.misunderstanding?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Evaluation(
            isCorrect: passes, score: score, mistakeCategory: category,
            feedback: ([judgement.feedback] + missed).joined(separator: "\n"),
            correctAnswer: challenge.expectedAnswer, explanation: challenge.explanation,
            misunderstanding: passes || (misunderstanding ?? "").isEmpty ? nil : misunderstanding,
            method: .criteria)
    }

    private func unverified(_ challenge: JavaChallenge, reason: String) -> Evaluation {
        Evaluation(
            isCorrect: nil, score: nil, mistakeCategory: .none,
            feedback: "\(reason) Compare your answer with the reference below and grade yourself.",
            correctAnswer: challenge.expectedAnswer, explanation: challenge.explanation, method: .unverified)
    }

    /// Turns an unverified evaluation into a self-graded one after the user compares against the reference.
    public static func selfGraded(_ evaluation: Evaluation, correct: Bool) -> Evaluation {
        var e = evaluation
        e.isCorrect = correct
        e.score = correct ? 1 : 0
        e.mistakeCategory = correct ? .none : .conceptual
        e.feedback = correct ? "Self-graded as correct." : "Self-graded as incorrect."
        e.method = .selfGraded
        return e
    }
}
