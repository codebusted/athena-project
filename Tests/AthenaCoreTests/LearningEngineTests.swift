import Foundation
import Testing
@testable import AthenaCore

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()
private let base = utc.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 9))!
private func day(_ n: Int) -> Date { utc.date(byAdding: .day, value: n, to: base)! }

private func attempt(_ correct: Bool, on date: Date, topic: Int64 = 1, type: ExerciseType = .predictOutput,
                     mistake: MistakeCategory = .conceptual, method: EvaluationMethod = .deterministic) -> ChallengeAttempt {
    ChallengeAttempt(id: 0, challengeId: UUID().uuidString, topicId: topic, exerciseType: type, difficulty: .easy,
                     userAnswer: "", isCorrect: method == .unverified ? nil : correct, score: correct ? 1 : 0,
                     mistakeCategory: correct ? .none : mistake, method: method, attemptedAt: date)
}

private let hashMap = Topic(id: 1, name: "HashMap", category: "Collections")
private let pq = Topic(id: 5, name: "PriorityQueue", category: "Queues")
private let generics = Topic(id: 13, name: "Generics", category: "Language fundamentals")

struct LearningEngineTests {
    let engine = LearningEngine(clock: DayClock(calendar: utc, now: { base }))

    @Test func newTopicHasNoProgress() {
        let p = engine.progress(for: hashMap, attempts: [])
        #expect(p.status == .new)
        #expect(p.attempts == 0)
        #expect(p.nextRevisionAt == nil)
    }

    @Test func unverifiedAttemptsAreIgnored() {
        let p = engine.progress(for: hashMap, attempts: [attempt(true, on: day(0), method: .unverified)])
        #expect(p.attempts == 0)
    }

    @Test func intervalsFollowAccuracyBands() {
        #expect(LearningEngine.intervalDays(mastery: 0.3, correctStreak: 0, lastMistake: nil) == 1)
        #expect(LearningEngine.intervalDays(mastery: 0.6, correctStreak: 0, lastMistake: nil) == 3)
        #expect(LearningEngine.intervalDays(mastery: 0.8, correctStreak: 0, lastMistake: nil) == 7)
        #expect(LearningEngine.intervalDays(mastery: 0.9, correctStreak: 0, lastMistake: nil) == 14)
        #expect(LearningEngine.intervalDays(mastery: 0.9, correctStreak: 3, lastMistake: nil) == 28)
        #expect(LearningEngine.intervalDays(mastery: 0.9, correctStreak: 0, lastMistake: .conceptual) == 1)
        #expect(LearningEngine.intervalDays(mastery: 0.9, correctStreak: 0, lastMistake: .careless) == 3)
    }

    @Test func singleOldMistakeFades() {
        let history = [attempt(false, on: day(-20))] + (1...5).map { attempt(true, on: day(-20 + $0 * 3)) }
        let p = engine.progress(for: hashMap, attempts: history)
        #expect(p.status == .strong)
        #expect(p.recentAccuracy == 1.0)  // the old miss is outside the recent window
    }

    @Test func recentMistakesOutweighOldSuccess() {
        let history = (0..<6).map { attempt(true, on: day(-30 + $0)) } + [attempt(false, on: day(-2)), attempt(false, on: day(-1))]
        let p = engine.progress(for: pq, attempts: history)
        #expect(p.status != .strong)
        #expect(p.mastery < 0.7)
        #expect(p.intervalDays == 1)
    }

    @Test func fewAttemptsShrinkTowardMiddle() {
        let one = engine.progress(for: hashMap, attempts: [attempt(true, on: day(-1))])
        #expect(one.status == .improving)
        let oneWrong = engine.progress(for: hashMap, attempts: [attempt(false, on: day(-1))])
        #expect(oneWrong.status == .needsPractice)
    }

    @Test func weakDueTopicBeatsStrongTopic() {
        let strong = engine.progress(for: hashMap, attempts: (0..<5).map { attempt(true, on: day(-10 + $0)) })
        let weak = engine.progress(for: pq, attempts: [attempt(false, on: day(-3)), attempt(false, on: day(-2)), attempt(true, on: day(-4))])
        let ranked = engine.rankedCandidates([strong, weak], settings: .init(), now: base)
        #expect(ranked.first?.progress.topic.name == "PriorityQueue")
    }

    @Test func focusAndExcludeAreRespected() {
        let a = engine.progress(for: hashMap, attempts: [])
        let b = engine.progress(for: generics, attempts: [])
        let focused = engine.nextExercise(progress: [a, b], attempts: [], settings: .init(focusTopics: ["generics"]), now: base)
        #expect(focused?.topic == "Generics")
        let excluded = engine.nextExercise(progress: [a, b], attempts: [], settings: .init(excludedTopics: ["HashMap", "Generics"]), now: base)
        #expect(excluded == nil)
    }

    @Test func practisedTodayIsDeprioritised() {
        let today = engine.progress(for: pq, attempts: [attempt(false, on: base)])
        let fresh = engine.progress(for: hashMap, attempts: [])
        #expect(engine.rankedCandidates([today, fresh], settings: .init(), now: base).first?.progress.topic.id == hashMap.id)
    }

    @Test func selectionIsDeterministic() {
        let progress = [hashMap, pq, generics].map { engine.progress(for: $0, attempts: []) }
        let first = engine.nextExercise(progress: progress, attempts: [], settings: .init(), now: base)
        for _ in 0..<5 {
            #expect(engine.nextExercise(progress: progress, attempts: [], settings: .init(), now: base) == first)
        }
        #expect(first?.topic == "HashMap")  // ties break by topic order
        #expect(first?.difficulty == .easy)
    }

    @Test func exerciseTypesRotate() {
        let history = [attempt(true, on: day(-2), type: .predictOutput)]
        #expect(LearningEngine.exerciseType(topicId: 1, attempts: history, allowed: []) == .apiRecall)
        #expect(LearningEngine.exerciseType(topicId: 1, attempts: history, allowed: [.predictOutput]) == .predictOutput)
    }

    @Test func difficultyScalesWithMastery() {
        let strong = engine.progress(for: hashMap, attempts: (0..<6).map { attempt(true, on: day(-10 + $0)) })
        #expect(LearningEngine.difficulty(for: strong) == .hard)
        #expect(engine.nextExercise(progress: [strong], attempts: [], settings: .init(difficultyOverride: .easy), now: base)?.difficulty == .easy)
    }
}
