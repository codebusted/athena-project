import Foundation
import Testing
@testable import AthenaCore

struct ChallengeEvaluatorTests {
    let evaluator = ChallengeEvaluator(ollama: nil)  // no LLM: exercises the deterministic and fallback paths

    func bank(_ id: String) -> JavaChallenge { QuestionBank.all.first { $0.id == id }! }

    @Test func outputNormalisationIgnoresLayout() async {
        let c = bank("bank-exc-1")  // expected "B\nC"
        #expect(await evaluator.evaluate(c, answer: "B C").isCorrect == true)
        #expect(await evaluator.evaluate(c, answer: "  B\n C ").isCorrect == true)
        #expect(await evaluator.evaluate(c, answer: "A B C").isCorrect == false)
    }

    @Test func listOutputMustMatchExactly() async {
        let c = bank("bank-list-1")
        #expect(await evaluator.evaluate(c, answer: "[10, 30]").isCorrect == true)
        #expect(await evaluator.evaluate(c, answer: "[10, 20, 30]").isCorrect == false)
    }

    @Test func apiRecallAcceptsCallForms() async {
        let c = bank("bank-map-r1")
        for answer in ["getOrDefault", "map.getOrDefault(key, 0)", "getOrDefault()", "GETORDEFAULT;"] {
            #expect(await evaluator.evaluate(c, answer: answer).isCorrect == true, "\(answer)")
        }
        #expect(await evaluator.evaluate(c, answer: "get").isCorrect == false)
    }

    @Test func qualifiedRecallRequiresQualifier() async {
        let c = bank("bank-sort-r1")  // Arrays.sort
        #expect(await evaluator.evaluate(c, answer: "Arrays.sort(arr)").isCorrect == true)
        #expect(await evaluator.evaluate(c, answer: "Collections.sort(arr)").isCorrect == false)
    }

    @Test func expressionRecallAcceptsAlternatives() async {
        let c = bank("bank-pq-r1")
        #expect(await evaluator.evaluate(c, answer: "PriorityQueue<Integer> pq = new PriorityQueue<>(Collections.reverseOrder());").isCorrect == true)
        #expect(await evaluator.evaluate(c, answer: "new PriorityQueue<>((a,b) -> b - a)").isCorrect == true)
        #expect(await evaluator.evaluate(c, answer: "new PriorityQueue<>()").isCorrect == false)
    }

    @Test func wrongDeterministicAnswerIsVerifiedIncorrect() async {
        let e = await evaluator.evaluate(bank("bank-pq-1"), answer: "1")
        #expect(e.isCorrect == false)
        #expect(e.method == .deterministic)
        #expect(e.correctAnswer == "2")
    }

    @Test func openEndedWithoutModelIsUnverified() async {
        let e = await evaluator.evaluate(bank("bank-eq-c1"), answer: "Because hash collections use hashCode first.")
        #expect(e.method == .unverified)
        #expect(e.isCorrect == nil)
        #expect(!e.method.countsTowardProgress)
        let graded = ChallengeEvaluator.selfGraded(e, correct: true)
        #expect(graded.method == .selfGraded && graded.isCorrect == true)
    }

    @Test func completeCodeExactMatchSkipsModel() async {
        let e = await evaluator.evaluate(bank("bank-cmp-c1"), answer: "Comparator.comparingInt(Person::age).thenComparing(Person::name)")
        #expect(e.isCorrect == true && e.method == .deterministic)
    }

    // MARK: LLM judgement validation

    typealias J = ChallengeEvaluator.CriteriaJudgement
    func judgement(_ met: [Bool], isCorrect: Bool, indices: [Int]? = nil) -> J {
        let json = """
            {"criteria":[\(zip(indices ?? Array(met.indices), met).map { "{\"index\":\($0),\"met\":\($1)}" }.joined(separator: ","))],
             "isCorrect":\(isCorrect),"mistakeCategory":"\(isCorrect ? "none" : "conceptual")","feedback":"ok","misunderstanding":""}
            """
        return try! JSONDecoder().decode(J.self, from: Data(json.utf8))
    }

    @Test func validJudgementIsAggregatedByApp() {
        let c = bank("bank-map-s1")  // 4 criteria
        let pass = ChallengeEvaluator.validate(judgement([true, true, true, false], isCorrect: true), for: c)
        #expect(pass?.isCorrect == true && pass?.score == 0.75 && pass?.method == .criteria)
        let fail = ChallengeEvaluator.validate(judgement([true, false, true, false], isCorrect: false), for: c)
        #expect(fail?.isCorrect == false && fail?.mistakeCategory == .conceptual)
    }

    @Test func modelCannotOverrideCriteria() {
        let c = bank("bank-map-s1")
        // Model says "correct" but only half the criteria are met → rejected, not accepted.
        #expect(ChallengeEvaluator.validate(judgement([true, false, true, false], isCorrect: true), for: c) == nil)
    }

    @Test func judgementMustCoverEveryCriterion() {
        let c = bank("bank-map-s1")
        #expect(ChallengeEvaluator.validate(judgement([true, true, true], isCorrect: true), for: c) == nil)
        #expect(ChallengeEvaluator.validate(judgement([true, true, true, true], isCorrect: true, indices: [0, 1, 1, 2]), for: c) == nil)
    }
}
