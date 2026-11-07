import Foundation

public final class ProgressRepository: Sendable {
    private let db: Database

    public init(db: Database) { self.db = db }

    public func topics() throws -> [Topic] {
        try db.query("SELECT id, name, category FROM topics ORDER BY id").map(Self.decodeTopic)
    }

    public func topic(named name: String) throws -> Topic? {
        try db.query("SELECT id, name, category FROM topics WHERE name = ? COLLATE NOCASE", [name])
            .first.map(Self.decodeTopic)
    }

    @discardableResult
    public func addTopic(name: String, category: String) throws -> Topic {
        try db.execute(
            "INSERT OR IGNORE INTO topics (name, category, created_at) VALUES (?, ?, ?)",
            [name, category, Timestamps.string(from: Date())])
        guard let topic = try topic(named: name) else { throw DatabaseError(message: "topic \(name) missing") }
        return topic
    }

    public func save(_ progress: TopicProgress) throws {
        try db.execute(
            """
            INSERT OR REPLACE INTO topic_progress (topic_id, attempts, correct_attempts, current_accuracy,
                recent_accuracy, mastery, status, interval_days, revision_count, last_practiced_at, next_revision_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [progress.topic.id, progress.attempts, progress.correctAttempts, progress.overallAccuracy,
             progress.recentAccuracy, progress.mastery, progress.status.rawValue, progress.intervalDays,
             progress.revisionCount, progress.lastPracticedAt.map(Timestamps.string(from:)),
             progress.nextRevisionAt.map(Timestamps.string(from:))])
    }

    private static func decodeTopic(_ row: Row) -> Topic {
        Topic(id: row["id"]?.int ?? 0, name: row["name"]?.string ?? "", category: row["category"]?.string ?? "")
    }
}

/// Key/value settings. Written by the app (snooze, autostart) and by the `athena` CLI (tuning).
public final class PreferencesRepository: Sendable {
    public enum Key: String, CaseIterable, Sendable {
        case model                 // Ollama model tag, default qwen3:4b
        case ollamaURL = "ollama_url"
        case think                 // "on" / "off"
        case difficulty            // auto / easy / medium / hard
        case focusTopics = "focus_topics"       // comma-separated topic names
        case excludedTopics = "excluded_topics" // comma-separated topic names
        case exerciseTypes = "exercise_types"   // comma-separated ExerciseType raw values
        case promptGuidance = "prompt_guidance" // free-text appended to the generation prompt
        case snoozeUntil = "snooze_until"       // ISO timestamp
        case autostartConfigured = "autostart_configured"
    }

    private let db: Database

    public init(db: Database) { self.db = db }

    public func get(_ key: Key) throws -> String? {
        try db.query("SELECT value FROM learning_preferences WHERE key = ?", [key.rawValue]).first?["value"]?.string
    }

    public func set(_ key: Key, _ value: String?) throws {
        if let value {
            try db.execute(
                "INSERT INTO learning_preferences (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                [key.rawValue, value])
        } else {
            try db.execute("DELETE FROM learning_preferences WHERE key = ?", [key.rawValue])
        }
    }

    public func list(_ key: Key) throws -> [String] {
        (try get(key) ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    public func setList(_ key: Key, _ values: [String]) throws {
        try set(key, values.isEmpty ? nil : values.joined(separator: ","))
    }

    public func all() throws -> [(String, String)] {
        try db.query("SELECT key, value FROM learning_preferences ORDER BY key").map {
            ($0["key"]?.string ?? "", $0["value"]?.string ?? "")
        }
    }

    public var model: String { ((try? get(.model)) ?? nil) ?? "qwen3:4b" }
    public var ollamaURL: URL { URL(string: ((try? get(.ollamaURL)) ?? nil) ?? "http://localhost:11434")! }
    public var thinkEnabled: Bool { ((try? get(.think)) ?? nil) == "on" }
}
