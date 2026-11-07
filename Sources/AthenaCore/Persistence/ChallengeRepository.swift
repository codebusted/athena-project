import Foundation

/// Stores generated/curated challenges (so a restart shows the same question) and every attempt.
public final class ChallengeRepository: Sendable {
    private let db: Database

    public init(db: Database) { self.db = db }

    public func save(_ challenge: JavaChallenge, topicId: Int64) throws {
        let json = String(decoding: try JSONEncoder().encode(challenge), as: UTF8.self)
        try db.execute(
            """
            INSERT OR REPLACE INTO challenges (id, topic_id, difficulty, exercise_type, source, json, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            [challenge.id, topicId, challenge.difficulty.rawValue, challenge.type.rawValue, challenge.source.rawValue,
             json, Timestamps.string(from: Date())])
    }

    public func challenge(id: String) throws -> JavaChallenge? {
        guard let json = try db.query("SELECT json FROM challenges WHERE id = ?", [id]).first?["json"]?.string else {
            return nil
        }
        return try JSONDecoder().decode(JavaChallenge.self, from: Data(json.utf8))
    }

    @discardableResult
    public func recordAttempt(
        challenge: JavaChallenge, topicId: Int64, userAnswer: String, evaluation: Evaluation, at date: Date = Date()
    ) throws -> Int64 {
        try db.execute(
            """
            INSERT INTO challenge_attempts (challenge_id, topic_id, exercise_type, difficulty, question, user_answer,
                expected_answer, is_correct, score, mistake_category, misunderstanding, feedback, evaluation_method,
                attempted_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [challenge.id, topicId, challenge.type.rawValue, challenge.difficulty.rawValue, challenge.question,
             userAnswer, evaluation.correctAnswer, evaluation.isCorrect, evaluation.score,
             evaluation.mistakeCategory.rawValue, evaluation.misunderstanding, evaluation.feedback,
             evaluation.method.rawValue, Timestamps.string(from: date)])
        return db.lastInsertRowId
    }

    public func attempts(topicId: Int64) throws -> [ChallengeAttempt] {
        try db.query(
            "SELECT * FROM challenge_attempts WHERE topic_id = ? ORDER BY attempted_at", [topicId]
        ).map(Self.decode)
    }

    public func allAttempts() throws -> [ChallengeAttempt] {
        try db.query("SELECT * FROM challenge_attempts ORDER BY attempted_at").map(Self.decode)
    }

    /// The most recent attempt for a challenge, so feedback survives an app restart.
    public func latestAttempt(challengeId: String) throws -> (attempt: ChallengeAttempt, feedback: String, misunderstanding: String?)? {
        guard let row = try db.query(
            "SELECT * FROM challenge_attempts WHERE challenge_id = ? ORDER BY attempted_at DESC LIMIT 1", [challengeId]
        ).first else { return nil }
        return (Self.decode(row), row["feedback"]?.string ?? "", row["misunderstanding"]?.string)
    }

    /// IDs of curated questions already served, so the bank rotates instead of repeating.
    public func usedChallengeIds() throws -> Set<String> {
        Set(try db.query("SELECT id FROM challenges").compactMap { $0["id"]?.string })
    }

    private static func decode(_ row: Row) -> ChallengeAttempt {
        ChallengeAttempt(
            id: row["id"]?.int ?? 0,
            challengeId: row["challenge_id"]?.string ?? "",
            topicId: row["topic_id"]?.int ?? 0,
            exerciseType: row["exercise_type"]?.string.flatMap(ExerciseType.init(rawValue:)),
            difficulty: row["difficulty"]?.string.flatMap(Difficulty.init(rawValue:)),
            userAnswer: row["user_answer"]?.string ?? "",
            isCorrect: row["is_correct"]?.bool,
            score: row["score"]?.double,
            mistakeCategory: MistakeCategory(loose: row["mistake_category"]?.string ?? "none"),
            method: row["evaluation_method"]?.string.flatMap(EvaluationMethod.init(rawValue:)) ?? .unverified,
            attemptedAt: row["attempted_at"]?.string.flatMap(Timestamps.date(from:)) ?? .distantPast)
    }
}
