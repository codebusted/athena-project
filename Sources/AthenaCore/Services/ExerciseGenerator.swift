import Foundation

public enum GenerationOutcome: Sendable {
    case generated(JavaChallenge)
    /// Fell back to the curated bank; `reason` explains why (shown subtly in the UI).
    case fallback(JavaChallenge, reason: String)

    public var challenge: JavaChallenge {
        switch self {
        case .generated(let c), .fallback(let c, _): c
        }
    }
}

/// Fills a scheduler-chosen `ExerciseRequest` with LLM-generated content, validates it, and falls back
/// to the curated bank after one retry.
public struct ExerciseGenerator: Sendable {
    private let ollama: OllamaService

    public init(ollama: OllamaService) { self.ollama = ollama }

    public func generate(
        _ request: ExerciseRequest, guidance: String?, recentQuestions: [String], usedBankIds: Set<String>
    ) async -> GenerationOutcome {
        var lastError = "generation failed"
        for _ in 0..<2 {
            // A cancelled background prefetch shouldn't fire off a retry request.
            if Task.isCancelled { break }
            do {
                let challenge = try await generateOnce(request, guidance: guidance, recentQuestions: recentQuestions)
                return .generated(challenge)
            } catch let error as OllamaError where error == .notRunning || error == .modelMissing(ollama.model) {
                lastError = error.localizedDescription
                break  // no point retrying
            } catch {
                lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            }
        }
        return fallback(request, usedBankIds: usedBankIds, reason: lastError)
    }

    public func fallback(_ request: ExerciseRequest, usedBankIds: Set<String>, reason: String) -> GenerationOutcome {
        let challenge = QuestionBank.pick(for: request, excluding: usedBankIds) ?? QuestionBank.all[0]
        return .fallback(challenge, reason: reason)
    }

    /// Small models don't always honour the schema for optional parts, so only the essentials are required.
    struct Draft: Decodable {
        let question: String
        let code: String
        let expectedAnswer: String
        let acceptableAnswers: [String]
        let explanation: String
        let evaluationCriteria: [String]

        init(question: String, code: String, expectedAnswer: String, acceptableAnswers: [String], explanation: String,
             evaluationCriteria: [String]) {
            self.question = question
            self.code = code
            self.expectedAnswer = expectedAnswer
            self.acceptableAnswers = acceptableAnswers
            self.explanation = explanation
            self.evaluationCriteria = evaluationCriteria
        }

        init(from decoder: Decoder) throws {
            enum K: String, CodingKey { case question, code, expectedAnswer, acceptableAnswers, explanation, evaluationCriteria }
            let c = try decoder.container(keyedBy: K.self)
            question = try c.decode(String.self, forKey: .question)
            code = try c.decodeIfPresent(String.self, forKey: .code) ?? ""
            expectedAnswer = try c.decode(String.self, forKey: .expectedAnswer)
            acceptableAnswers = (try? c.decodeIfPresent([String].self, forKey: .acceptableAnswers)) ?? []
            explanation = try c.decodeIfPresent(String.self, forKey: .explanation) ?? ""
            evaluationCriteria = (try? c.decodeIfPresent([String].self, forKey: .evaluationCriteria)) ?? []
        }
    }

    struct ValidationError: Error, LocalizedError {
        let reason: String
        var errorDescription: String? { "Generated exercise rejected: \(reason)" }
    }

    private func generateOnce(_ request: ExerciseRequest, guidance: String?, recentQuestions: [String]) async throws -> JavaChallenge {
        let avoid = recentQuestions.isEmpty ? "" :
            "\nDo not repeat these recent questions:\n" + recentQuestions.prefix(5).map { "- \($0.prefix(140))" }.joined(separator: "\n")
        let tuning = guidance.map { "\nAdditional guidance from the learner: \($0)" } ?? ""
        let prompt = """
            Write one \(request.difficulty.rawValue) exercise.
            Topic: \(request.topic) (category: \(request.category))
            Exercise type: \(request.type.rawValue) — \(request.type.label)
            \(Prompts.typeInstructions(request.type))
            evaluationCriteria: 2-4 short, checkable statements a correct answer must satisfy.
            explanation: 1-3 sentences explaining why the expected answer is correct.\(avoid)\(tuning)
            """
        let draft = try await ollama.chatJSON(
            system: Prompts.generatorSystem, user: prompt, schema: Prompts.challengeSchema, temperature: 0.7,
            as: Draft.self)
        let challenge = try Self.validate(draft, for: request)

        if request.type == .predictOutput { try await crossCheckOutput(challenge) }
        return challenge
    }

    static func validate(_ draft: Draft, for request: ExerciseRequest) throws -> JavaChallenge {
        func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        let question = clean(draft.question)
        var code = clean(draft.code.replacingOccurrences(of: "```java", with: "").replacingOccurrences(of: "```", with: ""))
        // Small models sometimes echo the question into `code` (e.g. as a println); that's noise, not a snippet.
        if code.contains(String(question.prefix(30))) { code = "" }
        let expected = clean(draft.expectedAnswer)
        let criteria = draft.evaluationCriteria.map(clean).filter { !$0.isEmpty }

        guard question.count >= 10, question.count <= 1200 else { throw ValidationError(reason: "question length") }
        guard !expected.isEmpty, expected.count <= 2000 else { throw ValidationError(reason: "expected answer missing") }
        guard code.count <= 2500, code.split(separator: "\n").count <= 30 else { throw ValidationError(reason: "code too long") }
        guard !clean(draft.explanation).isEmpty else { throw ValidationError(reason: "missing explanation") }

        let needsCode: Set<ExerciseType> = [.predictOutput, .identifyBug, .fixCode, .completeCode]
        if needsCode.contains(request.type), code.isEmpty { throw ValidationError(reason: "missing code") }
        switch request.type {
        case .predictOutput:
            guard expected.count <= 300 else { throw ValidationError(reason: "output too long") }
        case .apiRecall:
            guard expected.count <= 120 else { throw ValidationError(reason: "recall answer too long") }
        case .completeCode:
            guard code.contains("__") else { throw ValidationError(reason: "no blank in code") }
            guard (1...6).contains(criteria.count) else { throw ValidationError(reason: "criteria count") }
        case .identifyBug, .fixCode, .explainConcept, .smallCoding:
            guard (1...6).contains(criteria.count) else { throw ValidationError(reason: "criteria count") }
        }

        return JavaChallenge(
            id: "llm-" + UUID().uuidString.lowercased(), topic: request.topic, difficulty: request.difficulty,
            type: request.type, question: question, code: code.isEmpty ? nil : code, expectedAnswer: expected,
            acceptableAnswers: draft.acceptableAnswers.map(clean).filter { !$0.isEmpty },
            explanation: clean(draft.explanation), evaluationCriteria: criteria, source: .llm)
    }

    /// Small models often get their own predict-output answers wrong. Ask again independently (with reasoning
    /// enabled) and keep the exercise only if both answers agree.
    private func crossCheckOutput(_ challenge: JavaChallenge) async throws {
        struct Check: Decodable { let output: String }
        let prompt = """
            Trace this Java code carefully (it is the body of main with java.util.* imported) and give its exact stdout.
            \(challenge.code ?? "")
            """
        let check = try await ollama.chatJSON(
            system: Prompts.evaluatorSystem, user: prompt, schema: Prompts.outputCheckSchema, think: true,
            temperature: 0, as: Check.self)
        guard ChallengeEvaluator.normalizeOutput(check.output) == ChallengeEvaluator.normalizeOutput(challenge.expectedAnswer)
        else { throw ValidationError(reason: "expected output failed cross-check") }
    }
}
