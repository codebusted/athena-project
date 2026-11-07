import Foundation

/// Schema migrations keyed by `PRAGMA user_version`. Append new migrations; never edit shipped ones.
enum DatabaseSchema {
    static let migrations: [String] = [
        // v1
        """
        CREATE TABLE daily_sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_date TEXT NOT NULL UNIQUE,          -- local calendar day, yyyy-MM-dd
            leetcode_problem_id TEXT,
            leetcode_title TEXT,
            leetcode_slug TEXT,
            leetcode_difficulty TEXT,
            leetcode_challenge_date TEXT,               -- LeetCode's own (UTC) date for the problem
            leetcode_completed INTEGER NOT NULL DEFAULT 0,
            java_challenge_id TEXT,
            java_completed INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );

        CREATE TABLE topics (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE COLLATE NOCASE,
            category TEXT NOT NULL,
            created_at TEXT NOT NULL
        );

        CREATE TABLE challenges (
            id TEXT PRIMARY KEY,
            topic_id INTEGER NOT NULL REFERENCES topics(id),
            difficulty TEXT NOT NULL,
            exercise_type TEXT NOT NULL,
            source TEXT NOT NULL,
            json TEXT NOT NULL,
            created_at TEXT NOT NULL
        );

        CREATE TABLE challenge_attempts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            challenge_id TEXT NOT NULL,
            topic_id INTEGER NOT NULL REFERENCES topics(id),
            exercise_type TEXT,
            difficulty TEXT,
            question TEXT,
            user_answer TEXT,
            expected_answer TEXT,
            is_correct INTEGER,                         -- NULL when the verdict could not be verified
            score REAL,
            mistake_category TEXT,
            misunderstanding TEXT,
            feedback TEXT,
            evaluation_method TEXT NOT NULL,
            attempted_at TEXT NOT NULL
        );
        CREATE INDEX idx_attempts_topic ON challenge_attempts(topic_id, attempted_at);

        -- Cache derived from challenge_attempts by LearningEngine; safe to rebuild at any time.
        CREATE TABLE topic_progress (
            topic_id INTEGER PRIMARY KEY REFERENCES topics(id),
            attempts INTEGER NOT NULL DEFAULT 0,
            correct_attempts INTEGER NOT NULL DEFAULT 0,
            current_accuracy REAL NOT NULL DEFAULT 0,
            recent_accuracy REAL NOT NULL DEFAULT 0,
            mastery REAL NOT NULL DEFAULT 0,
            status TEXT NOT NULL DEFAULT 'New',
            interval_days INTEGER NOT NULL DEFAULT 0,
            revision_count INTEGER NOT NULL DEFAULT 0,
            last_practiced_at TEXT,
            next_revision_at TEXT
        );

        CREATE TABLE learning_preferences (
            key TEXT PRIMARY KEY,
            value TEXT
        );
        """,
    ]

    static let initialTopics: [(String, String)] = [
        ("HashMap", "Collections"),
        ("HashSet", "Collections"),
        ("ArrayList", "Collections"),
        ("LinkedList", "Collections"),
        ("PriorityQueue", "Queues"),
        ("ArrayDeque", "Queues"),
        ("String", "Strings"),
        ("StringBuilder", "Strings"),
        ("Sorting", "Coding fluency"),
        ("Comparators", "Coding fluency"),
        ("Java exceptions", "Language fundamentals"),
        ("equals and hashCode", "Language fundamentals"),
        ("Generics", "Language fundamentals"),
        ("Java collection APIs", "Java APIs"),
    ]

    static func migrate(_ db: Database) throws {
        let current = Int(try db.query("PRAGMA user_version").first?["user_version"]?.int ?? 0)
        guard current < migrations.count else { return }
        try db.transaction {
            for version in current..<migrations.count {
                for statement in migrations[version].components(separatedBy: ";\n") {
                    let sql = statement.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !sql.isEmpty { try db.execute(sql) }
                }
                if version == 0 {
                    let now = Timestamps.string(from: Date())
                    for (name, category) in initialTopics {
                        try db.execute(
                            "INSERT OR IGNORE INTO topics (name, category, created_at) VALUES (?, ?, ?)",
                            [name, category, now])
                    }
                }
            }
            try db.execute("PRAGMA user_version = \(migrations.count)")
        }
    }
}
