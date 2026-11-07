import Foundation
import SQLite3

public enum SQLValue: Equatable, Sendable {
    case null
    case int(Int64)
    case double(Double)
    case text(String)

    public var string: String? { if case .text(let s) = self { s } else { nil } }
    public var int: Int64? {
        switch self {
        case .int(let i): i
        case .double(let d): Int64(d)
        default: nil
        }
    }
    public var double: Double? {
        switch self {
        case .double(let d): d
        case .int(let i): Double(i)
        default: nil
        }
    }
    public var bool: Bool? { int.map { $0 != 0 } }
}

public protocol SQLConvertible { var sqlValue: SQLValue { get } }
extension String: SQLConvertible { public var sqlValue: SQLValue { .text(self) } }
extension Int: SQLConvertible { public var sqlValue: SQLValue { .int(Int64(self)) } }
extension Int64: SQLConvertible { public var sqlValue: SQLValue { .int(self) } }
extension Double: SQLConvertible { public var sqlValue: SQLValue { .double(self) } }
extension Bool: SQLConvertible { public var sqlValue: SQLValue { .int(self ? 1 : 0) } }
extension SQLValue: SQLConvertible { public var sqlValue: SQLValue { self } }
extension Optional: SQLConvertible where Wrapped: SQLConvertible {
    public var sqlValue: SQLValue { self?.sqlValue ?? .null }
}

public typealias Row = [String: SQLValue]

public struct DatabaseError: Error, LocalizedError, Sendable {
    public let message: String
    public var errorDescription: String? { "Database error: \(message)" }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Thin wrapper over the SQLite C API. All access is serialised by a lock, so the same instance
/// can be used from the main actor and background tasks. The app and the CLI open separate
/// connections to the same file; WAL + busy_timeout keep that safe.
public final class Database: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let lock = NSRecursiveLock()
    public let path: String

    /// Default location shared by the app and the `athena` CLI.
    public static var defaultURL: URL {
        if let override = ProcessInfo.processInfo.environment["ATHENA_DB"] {
            return URL(fileURLWithPath: override)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Athena", isDirectory: true).appendingPathComponent("athena.sqlite")
    }

    public init(path: String) throws {
        self.path = path
        if path != ":memory:" {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unable to open \(path)"
            sqlite3_close(handle)
            throw DatabaseError(message: message)
        }
        sqlite3_busy_timeout(handle, 3000)
        try execute("PRAGMA foreign_keys = ON")
        if path != ":memory:" { _ = try query("PRAGMA journal_mode = WAL") }
        try DatabaseSchema.migrate(self)
    }

    public static func openDefault() throws -> Database {
        try Database(path: defaultURL.path)
    }

    deinit { sqlite3_close(handle) }

    public func execute(_ sql: String, _ params: [any SQLConvertible] = []) throws {
        _ = try query(sql, params)
    }

    @discardableResult
    public func query(_ sql: String, _ params: [any SQLConvertible] = []) throws -> [Row] {
        lock.lock()
        defer { lock.unlock() }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw lastError(sql) }
        defer { sqlite3_finalize(statement) }

        for (index, param) in params.enumerated() {
            let position = Int32(index + 1)
            let rc: Int32
            switch param.sqlValue {
            case .null: rc = sqlite3_bind_null(statement, position)
            case .int(let v): rc = sqlite3_bind_int64(statement, position, v)
            case .double(let v): rc = sqlite3_bind_double(statement, position, v)
            case .text(let v): rc = sqlite3_bind_text(statement, position, v, -1, SQLITE_TRANSIENT)
            }
            guard rc == SQLITE_OK else { throw lastError(sql) }
        }

        var rows: [Row] = []
        while true {
            let rc = sqlite3_step(statement)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw lastError(sql) }
            var row: Row = [:]
            for column in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, column))
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER: row[name] = .int(sqlite3_column_int64(statement, column))
                case SQLITE_FLOAT: row[name] = .double(sqlite3_column_double(statement, column))
                case SQLITE_TEXT: row[name] = .text(String(cString: sqlite3_column_text(statement, column)))
                default: row[name] = .null
                }
            }
            rows.append(row)
        }
        return rows
    }

    public var lastInsertRowId: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return sqlite3_last_insert_rowid(handle)
    }

    /// Runs `body` atomically. Nested calls join the outer transaction.
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        let isOutermost = sqlite3_get_autocommit(handle) != 0
        if isOutermost { try execute("BEGIN IMMEDIATE") }
        do {
            let result = try body()
            if isOutermost { try execute("COMMIT") }
            return result
        } catch {
            if isOutermost { try? execute("ROLLBACK") }
            throw error
        }
    }

    private func lastError(_ sql: String) -> DatabaseError {
        DatabaseError(message: "\(String(cString: sqlite3_errmsg(handle))) [\(sql.prefix(80))]")
    }
}
