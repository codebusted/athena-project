import Foundation

public final class SessionRepository: Sendable {
    private let db: Database

    public init(db: Database) { self.db = db }

    public func session(for day: String) throws -> DailySession? {
        try db.query("SELECT * FROM daily_sessions WHERE session_date = ?", [day]).first.map(Self.decode)
    }

    /// Returns the day's session, creating an empty one if needed.
    public func ensureSession(for day: String) throws -> DailySession {
        let now = Timestamps.string(from: Date())
        try db.execute(
            "INSERT OR IGNORE INTO daily_sessions (session_date, created_at, updated_at) VALUES (?, ?, ?)",
            [day, now, now])
        guard let session = try session(for: day) else { throw DatabaseError(message: "session \(day) missing") }
        return session
    }

    public func saveLeetCodeProblem(_ problem: LeetCodeProblem, for day: String) throws {
        _ = try ensureSession(for: day)
        try db.execute(
            """
            UPDATE daily_sessions SET leetcode_problem_id = ?, leetcode_title = ?, leetcode_slug = ?,
                leetcode_difficulty = ?, leetcode_challenge_date = ?, updated_at = ?
            WHERE session_date = ?
            """,
            [problem.frontendId, problem.title, problem.slug, problem.difficulty, problem.challengeDate,
             Timestamps.string(from: Date()), day])
    }

    public func setLeetCodeCompleted(_ completed: Bool, for day: String) throws {
        _ = try ensureSession(for: day)
        try db.execute(
            "UPDATE daily_sessions SET leetcode_completed = ?, updated_at = ? WHERE session_date = ?",
            [completed, Timestamps.string(from: Date()), day])
    }

    public func setJavaChallenge(id: String?, for day: String) throws {
        _ = try ensureSession(for: day)
        try db.execute(
            "UPDATE daily_sessions SET java_challenge_id = ?, updated_at = ? WHERE session_date = ?",
            [id, Timestamps.string(from: Date()), day])
    }

    public func setJavaCompleted(_ completed: Bool, for day: String) throws {
        _ = try ensureSession(for: day)
        try db.execute(
            "UPDATE daily_sessions SET java_completed = ?, updated_at = ? WHERE session_date = ?",
            [completed, Timestamps.string(from: Date()), day])
    }

    /// Sessions whose `session_date` falls in [from, to] (inclusive, yyyy-MM-dd strings sort chronologically).
    public func sessions(from: String, to: String) throws -> [DailySession] {
        try db.query(
            "SELECT * FROM daily_sessions WHERE session_date BETWEEN ? AND ? ORDER BY session_date", [from, to]
        ).map(Self.decode)
    }

    public func completedDays() throws -> [String] {
        try db.query(
            "SELECT session_date FROM daily_sessions WHERE leetcode_completed = 1 AND java_completed = 1 ORDER BY session_date"
        ).compactMap { $0["session_date"]?.string }
    }

    public func totals() throws -> (leetcode: Int, java: Int) {
        let row = try db.query(
            "SELECT SUM(leetcode_completed) AS lc, SUM(java_completed) AS jv FROM daily_sessions"
        ).first
        return (Int(row?["lc"]?.int ?? 0), Int(row?["jv"]?.int ?? 0))
    }

    /// Consecutive fully-completed days ending today, or ending yesterday if today is still in progress.
    public func currentStreak(today: String, clock: DayClock) throws -> Int {
        let done = Set(try completedDays())
        var cursor = done.contains(today) ? today : clock.day(today, offsetBy: -1)
        var streak = 0
        while done.contains(cursor) {
            streak += 1
            cursor = clock.day(cursor, offsetBy: -1)
        }
        return streak
    }

    public func longestStreak(clock: DayClock) throws -> Int {
        let days = try completedDays()
        var best = 0
        var run = 0
        var previous: String?
        for day in days {
            run = (previous.map { clock.day($0, offsetBy: 1) == day } ?? false) ? run + 1 : 1
            best = max(best, run)
            previous = day
        }
        return best
    }

    private static func decode(_ row: Row) -> DailySession {
        DailySession(
            date: row["session_date"]?.string ?? "",
            leetcodeProblemId: row["leetcode_problem_id"]?.string,
            leetcodeTitle: row["leetcode_title"]?.string,
            leetcodeSlug: row["leetcode_slug"]?.string,
            leetcodeDifficulty: row["leetcode_difficulty"]?.string,
            leetcodeChallengeDate: row["leetcode_challenge_date"]?.string,
            leetcodeCompleted: row["leetcode_completed"]?.bool ?? false,
            javaChallengeId: row["java_challenge_id"]?.string,
            javaCompleted: row["java_completed"]?.bool ?? false)
    }
}
