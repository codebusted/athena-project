import Foundation

/// Application layer shared by the app and the CLI. Owns the repositories and wires the
/// deterministic engine to the LLM-backed generator/evaluator.
public final class AthenaStore: Sendable {
    public let db: Database
    public let sessions: SessionRepository
    public let challenges: ChallengeRepository
    public let progressRepo: ProgressRepository
    public let preferences: PreferencesRepository
    public let clock: DayClock
    public let engine: LearningEngine

    public init(db: Database, clock: DayClock = DayClock()) {
        self.db = db
        self.clock = clock
        sessions = SessionRepository(db: db)
        challenges = ChallengeRepository(db: db)
        progressRepo = ProgressRepository(db: db)
        preferences = PreferencesRepository(db: db)
        engine = LearningEngine(clock: clock)
    }

    public static func openDefault() throws -> AthenaStore { AthenaStore(db: try Database.openDefault()) }

    public var today: String { clock.today }

    public func ollama() -> OllamaService {
        OllamaService(baseURL: preferences.ollamaURL, model: preferences.model, think: preferences.thinkEnabled)
    }

    public func engineSettings() throws -> LearningEngine.Settings {
        LearningEngine.Settings(
            focusTopics: Set(try preferences.list(.focusTopics)),
            excludedTopics: Set(try preferences.list(.excludedTopics)),
            allowedTypes: try preferences.list(.exerciseTypes).compactMap(ExerciseType.init(rawValue:)),
            difficultyOverride: try preferences.get(.difficulty).flatMap(Difficulty.init(loose:)))
    }

    // MARK: Progress

    /// Recomputes every topic's progress from attempts and refreshes the `topic_progress` cache.
    public func allProgress() throws -> [TopicProgress] {
        let attempts = Dictionary(grouping: try challenges.allAttempts(), by: \.topicId)
        let result = try progressRepo.topics().map { engine.progress(for: $0, attempts: attempts[$0.id] ?? []) }
        try db.transaction { for p in result { try progressRepo.save(p) } }
        return result
    }

    public func summary(now: Date = Date()) throws -> LearningSummary {
        LearningSummary(progress: try allProgress(), clock: clock, now: now)
    }

    /// The scheduler's next pick. `avoidingTopics` are skipped when possible (e.g. the topic already on screen,
    /// whose result isn't recorded yet); if that would leave nothing to pick, they're allowed again.
    public func nextRequest(avoidingTopics: Set<String> = [], now: Date = Date()) throws -> ExerciseRequest {
        let fallback = ExerciseRequest(topic: "HashMap", category: "Collections", difficulty: .easy, type: .predictOutput)
        let progress = try allProgress()
        let attempts = try challenges.allAttempts()
        let settings = try engineSettings()
        var avoiding = settings
        avoiding.excludedTopics.formUnion(avoidingTopics.map { $0.lowercased() })
        return engine.nextExercise(progress: progress, attempts: attempts, settings: avoiding, now: now)
            ?? engine.nextExercise(progress: progress, attempts: attempts, settings: settings, now: now)
            ?? fallback
    }

    // MARK: Java challenge

    /// Today's challenge if one was already chosen (survives restarts).
    public func storedChallenge(for day: String) throws -> JavaChallenge? {
        guard let id = try sessions.session(for: day)?.javaChallengeId else { return nil }
        return try challenges.challenge(id: id)
    }

    /// Picks a topic deterministically, asks the LLM to write the exercise (or uses the bank) and stores it.
    /// `assignToDay` is nil for extra practice beyond the daily exercise.
    public func makeChallenge(assignToDay day: String?, useBankOnly: Bool = false, now: Date = Date()) async throws
        -> GenerationOutcome
    {
        let outcome = try await prepareChallenge(useBankOnly: useBankOnly, now: now)
        // The user may have switched to a saved question while generation was running.
        try Task.checkCancellation()
        try adopt(outcome.challenge, assignToDay: day)
        return outcome
    }

    /// Writes an exercise without saving it, so it can be prepared in the background (prefetch) and adopted
    /// later. `avoiding` keeps it away from what's currently on screen: a different topic, and never the same question.
    public func prepareChallenge(useBankOnly: Bool = false, avoiding current: JavaChallenge? = nil, now: Date = Date())
        async throws -> GenerationOutcome
    {
        let request = try nextRequest(avoidingTopics: current.map { [$0.topic] } ?? [], now: now)
        let generator = ExerciseGenerator(ollama: ollama())
        var used = try challenges.usedChallengeIds()
        if let current { used.insert(current.id) }
        if useBankOnly {
            return generator.fallback(request, usedBankIds: used, reason: "Using a saved question.")
        }
        // Most recent first: the generator only passes the first few on to the model.
        var recent = try challenges.allAttempts().suffix(10).reversed()
            .compactMap { try? challenges.challenge(id: $0.challengeId)?.question }
        if let current { recent.insert(current.question, at: 0) }
        return await generator.generate(
            request, guidance: try preferences.get(.promptGuidance), recentQuestions: recent, usedBankIds: used)
    }

    /// Saves a prepared exercise, optionally as the given day's Java Daily.
    public func adopt(_ challenge: JavaChallenge, assignToDay day: String?) throws {
        let category = DatabaseSchema.initialTopics.first { $0.0.caseInsensitiveCompare(challenge.topic) == .orderedSame }?.1
        let topic = try progressRepo.topic(named: challenge.topic)
            ?? progressRepo.addTopic(name: challenge.topic, category: category ?? "Other")
        try db.transaction {
            try challenges.save(challenge, topicId: topic.id)
            if let day { try sessions.setJavaChallenge(id: challenge.id, for: day) }
        }
    }

    public func evaluate(_ challenge: JavaChallenge, answer: String) async -> Evaluation {
        await ChallengeEvaluator(ollama: ollama()).evaluate(challenge, answer: answer)
    }

    /// Persists an attempt. Unverified evaluations are stored for history but do not complete the task or move scores;
    /// the caller should self-grade them first.
    public func record(_ challenge: JavaChallenge, answer: String, evaluation: Evaluation, day: String?) throws {
        let topic = try progressRepo.topic(named: challenge.topic)
            ?? progressRepo.addTopic(name: challenge.topic, category: "Other")
        try db.transaction {
            try challenges.recordAttempt(challenge: challenge, topicId: topic.id, userAnswer: answer, evaluation: evaluation)
            if let day, evaluation.method.countsTowardProgress { try sessions.setJavaCompleted(true, for: day) }
        }
        _ = try allProgress()
    }

    public func revisionText(for topicName: String) throws -> String? {
        guard let p = try allProgress().first(where: { $0.topic.name.caseInsensitiveCompare(topicName) == .orderedSame }),
              p.attempts > 0 else { return nil }
        let when = p.intervalDays <= 1 ? "tomorrow" : "in \(p.intervalDays) days"
        let needs = p.status == .needsPractice || p.status == .improving
        return "\(p.topic.name): \(p.status.rawValue) (\(p.correctAttempts)/\(p.attempts)). " +
            (needs ? "Needs revision — back \(when)." : "Next revision \(when).")
    }

    // MARK: LeetCode

    /// Loads today's problem: uses the stored one, refetching only when nothing is stored or when LeetCode has rolled
    /// over to a new problem and today's has not been marked solved yet.
    public func refreshLeetCode(service: LeetCodeService = LeetCodeService()) async throws -> DailySession {
        let day = today
        let session = try sessions.ensureSession(for: day)
        let utcDay: String = {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "UTC")!
            return DayClock(calendar: cal).today
        }()
        let stale = session.leetcodeTitle == nil || (!session.leetcodeCompleted && session.leetcodeChallengeDate != utcDay)
        guard stale else { return session }
        let problem = try await service.fetchDailyProblem()
        try sessions.saveLeetCodeProblem(problem, for: day)
        return try sessions.ensureSession(for: day)
    }

    // MARK: Calendar

    public struct MonthDay: Sendable, Identifiable {
        public var id: String { date }
        public var date: String
        public var dayOfMonth: Int
        public var completed: Int  // 0, 1 or 2 activities
    }

    /// Days of the month containing `anchor`, with leading padding count for the first weekday.
    public func month(containing anchor: Date) throws -> (title: String, leadingBlanks: Int, days: [MonthDay]) {
        let cal = clock.calendar
        let start = cal.date(from: cal.dateComponents([.year, .month], from: anchor))!
        let count = cal.range(of: .day, in: .month, for: start)!.count
        let firstDay = clock.dayString(for: start)
        let lastDay = clock.day(firstDay, offsetBy: count - 1)
        let byDate = Dictionary(uniqueKeysWithValues: try sessions.sessions(from: firstDay, to: lastDay).map { ($0.date, $0) })
        let days = (0..<count).map { i -> MonthDay in
            let date = clock.day(firstDay, offsetBy: i)
            return MonthDay(date: date, dayOfMonth: i + 1, completed: byDate[date]?.completedCount ?? 0)
        }
        let weekday = cal.component(.weekday, from: start)
        let leading = (weekday - cal.firstWeekday + 7) % 7
        let formatter = DateFormatter()
        formatter.calendar = cal
        formatter.dateFormat = "LLLL yyyy"
        return (formatter.string(from: start), leading, days)
    }
}
