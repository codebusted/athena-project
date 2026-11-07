import Foundation

/// Deterministic learning logic: topic mastery, revision scheduling and next-exercise selection.
/// Everything here is computed from recorded attempts; the LLM has no say.
public struct LearningEngine: Sendable {
    public struct Settings: Sendable, Equatable {
        public var focusTopics: Set<String> = []
        public var excludedTopics: Set<String> = []
        public var allowedTypes: [ExerciseType] = []
        public var difficultyOverride: Difficulty?

        public init(focusTopics: Set<String> = [], excludedTopics: Set<String> = [], allowedTypes: [ExerciseType] = [],
                    difficultyOverride: Difficulty? = nil) {
            self.focusTopics = Set(focusTopics.map { $0.lowercased() })
            self.excludedTopics = Set(excludedTopics.map { $0.lowercased() })
            self.allowedTypes = allowedTypes
            self.difficultyOverride = difficultyOverride
        }
    }

    /// Reliable, deterministically graded types first; this order also breaks ties in type rotation.
    static let typeOrder: [ExerciseType] = [
        .predictOutput, .apiRecall, .identifyBug, .completeCode, .explainConcept, .smallCoding, .fixCode,
    ]
    static let priorityCategories: Set<String> = ["Collections", "Queues", "Coding fluency", "Strings", "Java APIs"]
    static let recentWindow = 5
    static let recentDecay = 0.75
    /// Fewer than this many verified attempts → mastery is shrunk toward 0.5 (not enough evidence).
    static let confidenceAttempts = 3

    public var clock: DayClock

    public init(clock: DayClock = DayClock()) { self.clock = clock }

    // MARK: Progress

    public func progress(for topic: Topic, attempts allAttempts: [ChallengeAttempt]) -> TopicProgress {
        let attempts = allAttempts
            .filter { $0.method.countsTowardProgress && $0.isCorrect != nil }
            .sorted { $0.attemptedAt < $1.attemptedAt }
        let n = attempts.count
        guard let last = attempts.last else {
            return TopicProgress(
                topic: topic, attempts: 0, correctAttempts: 0, overallAccuracy: 0, recentAccuracy: 0, mastery: 0,
                status: .new, lastPracticedAt: nil, nextRevisionAt: nil, intervalDays: 0, revisionCount: 0,
                commonMistake: nil)
        }

        let scores = attempts.map { $0.score ?? ($0.isCorrect == true ? 1 : 0) }
        let overall = scores.reduce(0, +) / Double(n)

        // Exponentially weighted over the last few attempts, most recent weighted highest,
        // so one old mistake fades instead of pinning a topic as weak forever.
        var weighted = 0.0
        var totalWeight = 0.0
        for (k, score) in scores.suffix(Self.recentWindow).reversed().enumerated() {
            let w = pow(Self.recentDecay, Double(k))
            weighted += w * score
            totalWeight += w
        }
        let recent = weighted / totalWeight

        var mastery = 0.7 * recent + 0.3 * overall
        if n < Self.confidenceAttempts {
            let c = Double(Self.confidenceAttempts)
            mastery = (Double(n) * mastery + (c - Double(n)) * 0.5) / c
        }

        let correctStreak = attempts.reversed().prefix { $0.isCorrect == true }.count
        let interval = Self.intervalDays(mastery: mastery, correctStreak: correctStreak,
                                         lastMistake: last.isCorrect == true ? nil : last.mistakeCategory)
        let mistakes = attempts.filter { $0.isCorrect == false && $0.mistakeCategory != .none }.map(\.mistakeCategory)
        let common = Dictionary(grouping: mistakes, by: { $0 })
            .max { $0.value.count == $1.value.count ? $0.key.rawValue > $1.key.rawValue : $0.value.count < $1.value.count }?.key

        return TopicProgress(
            topic: topic, attempts: n, correctAttempts: attempts.filter { $0.isCorrect == true }.count,
            overallAccuracy: overall, recentAccuracy: recent, mastery: mastery, status: Self.status(mastery: mastery),
            lastPracticedAt: last.attemptedAt,
            nextRevisionAt: clock.calendar.date(byAdding: .day, value: interval, to: last.attemptedAt),
            intervalDays: interval, revisionCount: n - 1, commonMistake: common)
    }

    static func status(mastery: Double) -> TopicStatus {
        switch mastery {
        case 0.85...: .strong
        case 0.70..<0.85: .good
        case 0.50..<0.70: .improving
        default: .needsPractice
        }
    }

    /// <50% → 1 day, 50–70% → 3, 70–85% → 7, ≥85% → 14. A run of 3+ correct answers doubles the interval
    /// (capped at 30). A fresh conceptual/API mistake brings the topic back tomorrow; a slip or edge case within 3 days.
    static func intervalDays(mastery: Double, correctStreak: Int, lastMistake: MistakeCategory?) -> Int {
        var days: Int = switch mastery {
        case ..<0.5: 1
        case 0.5..<0.7: 3
        case 0.7..<0.85: 7
        default: 14
        }
        if correctStreak >= 3 { days = min(days * 2, 30) }
        switch lastMistake {
        case .conceptual?, .apiMisuse?, .incomplete?: days = 1
        case .careless?, .edgeCase?, .syntax?: days = min(days, 3)
        default: break
        }
        return days
    }

    // MARK: Selection

    public struct Candidate: Sendable {
        public var progress: TopicProgress
        public var priority: Double
    }

    /// Higher is more urgent. Deterministic for identical inputs.
    public func priority(of p: TopicProgress, settings: Settings, now: Date) -> Double {
        let today = clock.dayString(for: now)
        let weakness = 1 - (p.attempts == 0 ? 0.5 : p.mastery)
        var score = weakness * 4

        if p.attempts == 0 {
            score += 2
        } else if let next = p.nextRevisionAt {
            let nextDay = clock.dayString(for: next)
            if nextDay <= today {
                let overdue = clock.calendar.dateComponents([.day], from: next, to: now).day ?? 0
                score += 2 + Double(min(max(overdue, 0), 7)) * 0.25
            } else {
                score -= 1.5
            }
        }
        if let last = p.lastPracticedAt {
            let day = clock.dayString(for: last)
            if day == today { score -= 3 } else if day == clock.day(today, offsetBy: -1) { score -= 1 }
        }
        if settings.focusTopics.contains(p.topic.name.lowercased()) { score += 3 }
        if Self.priorityCategories.contains(p.topic.category) { score += 0.5 }
        return score
    }

    public func rankedCandidates(_ progress: [TopicProgress], settings: Settings, now: Date) -> [Candidate] {
        progress
            .filter { !settings.excludedTopics.contains($0.topic.name.lowercased()) }
            .map { Candidate(progress: $0, priority: priority(of: $0, settings: settings, now: now)) }
            .sorted { $0.priority == $1.priority ? $0.progress.topic.id < $1.progress.topic.id : $0.priority > $1.priority }
    }

    public func nextExercise(progress: [TopicProgress], attempts: [ChallengeAttempt], settings: Settings,
                             now: Date) -> ExerciseRequest? {
        guard let chosen = rankedCandidates(progress, settings: settings, now: now).first?.progress else { return nil }
        return ExerciseRequest(
            topic: chosen.topic.name, category: chosen.topic.category,
            difficulty: settings.difficultyOverride ?? Self.difficulty(for: chosen),
            type: Self.exerciseType(topicId: chosen.topic.id, attempts: attempts, allowed: settings.allowedTypes))
    }

    static func difficulty(for p: TopicProgress) -> Difficulty {
        if p.attempts < 2 || p.mastery < 0.5 { return .easy }
        return p.mastery < 0.8 ? .medium : .hard
    }

    /// Rotates through exercise types: the least-practised type for this topic wins; ties follow `typeOrder`.
    static func exerciseType(topicId: Int64, attempts: [ChallengeAttempt], allowed: [ExerciseType]) -> ExerciseType {
        let pool = allowed.isEmpty ? typeOrder : typeOrder.filter(allowed.contains)
        guard !pool.isEmpty else { return .predictOutput }
        let counts = Dictionary(grouping: attempts.filter { $0.topicId == topicId }.compactMap(\.exerciseType), by: { $0 })
            .mapValues(\.count)
        return pool.min { (counts[$0] ?? 0, pool.firstIndex(of: $0)!) < (counts[$1] ?? 0, pool.firstIndex(of: $1)!) }!
    }
}

// MARK: - Summary

public struct LearningSummary: Sendable {
    public struct Line: Sendable, Identifiable {
        public var id: String { topic }
        public var topic: String
        public var status: TopicStatus
        public var detail: String
    }

    public var strong: [String]
    public var needsWork: [String]
    public var recent: [String]
    public var untouched: [String]
    public var lines: [Line]
    public var totalAttempts: Int
    public var overallAccuracy: Double?

    public init(progress: [TopicProgress], clock: DayClock, now: Date) {
        let practised = progress.filter { $0.attempts > 0 }
        strong = practised.filter { $0.status == .strong || $0.status == .good }.sorted { $0.mastery > $1.mastery }.map(\.topic.name)
        needsWork = practised.filter { $0.status == .needsPractice || $0.status == .improving }
            .sorted { $0.mastery < $1.mastery }.map(\.topic.name)
        recent = practised.sorted { ($0.lastPracticedAt ?? .distantPast) > ($1.lastPracticedAt ?? .distantPast) }
            .prefix(5).map(\.topic.name)
        untouched = progress.filter { $0.attempts == 0 }.map(\.topic.name)
        totalAttempts = practised.reduce(0) { $0 + $1.attempts }
        let correct = practised.reduce(0) { $0 + $1.correctAttempts }
        overallAccuracy = totalAttempts == 0 ? nil : Double(correct) / Double(totalAttempts)

        lines = practised.sorted { $0.mastery < $1.mastery }.map { p in
            var parts = ["\(p.correctAttempts)/\(p.attempts) correct", "recent \(Int((p.recentAccuracy * 100).rounded()))%"]
            if let last = p.lastPracticedAt { parts.append("last practised \(Self.relative(last, clock: clock, now: now))") }
            if let next = p.nextRevisionAt {
                let nextDay = clock.dayString(for: next)
                parts.append(nextDay <= clock.dayString(for: now) ? "revision due" : "next revision \(Self.relative(next, clock: clock, now: now))")
            }
            if let mistake = p.commonMistake { parts.append("most common mistake: \(mistake.label.lowercased())") }
            return Line(topic: p.topic.name, status: p.status, detail: parts.joined(separator: " · "))
        }
    }

    static func relative(_ date: Date, clock: DayClock, now: Date) -> String {
        let cal = clock.calendar
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return "today"
        case -1: return "yesterday"
        case 1: return "tomorrow"
        case ..<0: return "\(-days)d ago"
        default: return "in \(days)d"
        }
    }
}
