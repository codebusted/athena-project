import Foundation
import Testing
@testable import AthenaCore

struct DatabaseTests {
    func makeStore(today: String = "2026-11-07") throws -> AthenaStore {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let clock = DayClock(calendar: cal)
        let now = clock.date(fromDay: today)!.addingTimeInterval(12 * 3600)
        return AthenaStore(db: try Database(path: ":memory:"), clock: DayClock(calendar: cal, now: { now }))
    }

    @Test func migrationSeedsInitialTopics() throws {
        let store = try makeStore()
        let names = try store.progressRepo.topics().map(\.name)
        #expect(names.count == 14)
        #expect(names.first == "HashMap")
        #expect(try store.progressRepo.topic(named: "priorityqueue")?.name == "PriorityQueue")
    }

    @Test func migrationIsIdempotentOnDisk() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("athena-test-\(UUID()).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        _ = try Database(path: path)
        let reopened = try Database(path: path)
        #expect(try ProgressRepository(db: reopened).topics().count == 14)
    }

    @Test func streakCountsConsecutiveCompleteDays() throws {
        let store = try makeStore()
        for d in ["2026-11-04", "2026-11-05", "2026-11-06"] {
            try store.sessions.setLeetCodeCompleted(true, for: d)
            try store.sessions.setJavaCompleted(true, for: d)
        }
        try store.sessions.setLeetCodeCompleted(true, for: "2026-11-02")  // partial day, breaks nothing after
        // Today in progress: streak still counts through yesterday.
        #expect(try store.sessions.currentStreak(today: "2026-11-07", clock: store.clock) == 3)
        try store.sessions.setLeetCodeCompleted(true, for: "2026-11-07")
        try store.sessions.setJavaCompleted(true, for: "2026-11-07")
        #expect(try store.sessions.currentStreak(today: "2026-11-07", clock: store.clock) == 4)
        #expect(try store.sessions.longestStreak(clock: store.clock) == 4)
        #expect(try store.sessions.totals().leetcode == 5)
    }

    @Test func missedDayResetsStreak() throws {
        let store = try makeStore()
        try store.sessions.setLeetCodeCompleted(true, for: "2026-11-05")
        try store.sessions.setJavaCompleted(true, for: "2026-11-05")
        #expect(try store.sessions.currentStreak(today: "2026-11-07", clock: store.clock) == 0)
    }

    @Test func dailyChallengePersistsAndRecordsProgress() async throws {
        let store = try makeStore()
        let outcome = try await store.makeChallenge(assignToDay: store.today, useBankOnly: true)
        let challenge = outcome.challenge
        #expect(try store.storedChallenge(for: store.today) == challenge)

        let evaluation = await store.evaluate(challenge, answer: challenge.expectedAnswer)
        #expect(evaluation.isCorrect == true)
        try store.record(challenge, answer: challenge.expectedAnswer, evaluation: evaluation, day: store.today)

        #expect(try store.sessions.session(for: store.today)?.javaCompleted == true)
        let progress = try store.allProgress().first { $0.topic.name == challenge.topic }
        #expect(progress?.attempts == 1 && progress?.correctAttempts == 1)
        #expect(try store.challenges.latestAttempt(challengeId: challenge.id)?.attempt.isCorrect == true)
    }

    @Test func unverifiedAttemptDoesNotCompleteOrScore() throws {
        let store = try makeStore()
        let c = QuestionBank.all.first { $0.id == "bank-eq-c1" }!
        let e = Evaluation(isCorrect: nil, score: nil, mistakeCategory: .none, feedback: "", correctAnswer: "",
                           explanation: "", method: .unverified)
        try store.record(c, answer: "x", evaluation: e, day: store.today)
        #expect(try store.sessions.ensureSession(for: store.today).javaCompleted == false)
        #expect(try store.allProgress().first { $0.topic.name == c.topic }?.attempts == 0)
    }

    @Test func bankRotatesWithoutRepeating() async throws {
        let store = try makeStore()
        var seen = Set<String>()
        for _ in 0..<5 {
            let c = try await store.makeChallenge(assignToDay: nil, useBankOnly: true).challenge
            #expect(!seen.contains(c.id))
            seen.insert(c.id)
        }
    }

    @Test func prefetchedChallengeIsUnsavedAndAvoidsCurrent() async throws {
        let store = try makeStore()
        let current = try await store.makeChallenge(assignToDay: store.today, useBankOnly: true).challenge
        let next = try await store.prepareChallenge(useBankOnly: true, avoiding: current).challenge
        #expect(next.topic != current.topic)
        #expect(next.id != current.id)
        // Preparing doesn't save or change today's exercise.
        #expect(try store.challenges.challenge(id: next.id) == nil)
        #expect(try store.storedChallenge(for: store.today) == current)

        try store.adopt(next, assignToDay: nil)
        #expect(try store.challenges.challenge(id: next.id) == next)
        #expect(try store.storedChallenge(for: store.today) == current)  // extra practice isn't the daily one
    }

    @Test func avoidingEveryTopicFallsBackToNormalPick() throws {
        let store = try makeStore()
        let all = Set(try store.progressRepo.topics().map(\.name))
        #expect(try store.nextRequest(avoidingTopics: all).topic == store.nextRequest().topic)
    }

    @Test func preferencesRoundTrip() throws {
        let store = try makeStore()
        try store.preferences.setList(.focusTopics, ["PriorityQueue", "Generics"])
        try store.preferences.set(.difficulty, "Medium")
        let settings = try store.engineSettings()
        #expect(settings.focusTopics == ["priorityqueue", "generics"])
        #expect(settings.difficultyOverride == .medium)
        #expect(store.preferences.model == "qwen3:4b")
    }

    @Test func monthLayout() throws {
        let store = try makeStore()
        let month = try store.month(containing: store.clock.now())
        #expect(month.days.count == 30)  // November
        #expect(month.days.first?.date == "2026-11-01")
    }
}

struct OllamaParsingTests {
    @Test func extractsJSONFromNoisyOutput() {
        let raw = "<think>hmm { not this }</think>\n```json\n{\"output\": \"2\"}\n```"
        #expect(OllamaService.extractJSONObject(from: raw) == "{\"output\": \"2\"}")
        #expect(OllamaService.extractJSONObject(from: "no json here") == nil)
    }

    @Test func modelTagMatching() {
        #expect(OllamaService.modelIsAvailable("qwen3:4b", in: ["qwen3:4b", "gemma4:latest"]))
        #expect(OllamaService.modelIsAvailable("gemma4", in: ["gemma4:latest"]))
        #expect(!OllamaService.modelIsAvailable("qwen3:4b", in: ["gemma4:latest"]))
    }

    @Test func leetCodeParsing() throws {
        let json = #"{"data":{"activeDailyCodingChallengeQuestion":{"date":"2026-11-06","link":"/problems/x/","question":{"questionFrontendId":"2747","title":"Count Zero Request Servers","titleSlug":"count-zero-request-servers","difficulty":"Medium"}}}}"#
        let p = try LeetCodeService.parse(Data(json.utf8))
        #expect(p.title == "Count Zero Request Servers" && p.difficulty == "Medium")
        #expect(p.url.absoluteString == "https://leetcode.com/problems/count-zero-request-servers/")
        #expect(throws: (any Error).self) { try LeetCodeService.parse(Data(#"{"data":null}"#.utf8)) }
    }

    @Test func generatedDraftValidation() throws {
        let request = ExerciseRequest(topic: "HashMap", category: "Collections", difficulty: .easy, type: .predictOutput)
        let good = ExerciseGenerator.Draft(question: "What does this print?", code: "System.out.println(1);",
                                           expectedAnswer: "1", acceptableAnswers: [], explanation: "It prints 1.",
                                           evaluationCriteria: [])
        let c = try ExerciseGenerator.validate(good, for: request)
        #expect(c.source == .llm && c.topic == "HashMap")
        let noCode = ExerciseGenerator.Draft(question: "What does this print?", code: "", expectedAnswer: "1",
                                             acceptableAnswers: [], explanation: "x", evaluationCriteria: [])
        #expect(throws: (any Error).self) { try ExerciseGenerator.validate(noCode, for: request) }
    }

    @Test func echoedQuestionIsDroppedFromCode() throws {
        let request = ExerciseRequest(topic: "Comparators", category: "Coding fluency", difficulty: .easy, type: .apiRecall)
        let question = "Which Comparator method adds a secondary sort key?"
        let draft = ExerciseGenerator.Draft(question: question, code: "System.out.println(\"\(question)\");",
                                            expectedAnswer: "thenComparing", acceptableAnswers: [],
                                            explanation: "Adds a tie-breaker.", evaluationCriteria: [])
        #expect(try ExerciseGenerator.validate(draft, for: request).code == nil)
    }

    @Test func bankIsWellFormed() {
        let topics = Set(DatabaseSchema.initialTopics.map(\.0))
        #expect(Set(QuestionBank.all.map(\.id)).count == QuestionBank.all.count)
        for c in QuestionBank.all {
            #expect(topics.contains(c.topic), "\(c.id) topic")
            #expect(!c.expectedAnswer.isEmpty && !c.explanation.isEmpty, "\(c.id)")
            if !c.type.isDeterministic && c.type != .completeCode { #expect(!c.evaluationCriteria.isEmpty, "\(c.id) criteria") }
        }
        // Every initial topic has at least one fallback question.
        for t in topics { #expect(!QuestionBank.challenges(topic: t).isEmpty, "\(t) has no bank question") }
    }
}
