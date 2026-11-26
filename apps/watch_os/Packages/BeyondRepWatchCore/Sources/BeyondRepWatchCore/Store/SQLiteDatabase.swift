import Foundation
import SQLite3

enum SQLValue: Equatable {
    case text(String)
    case int(Int64)
    case null
}

struct SQLiteError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

/// A thin wrapper over the system SQLite: one connection, WAL, prepared
/// statements and explicit transactions.
final class SQLiteDatabase {
    private var handle: OpaquePointer?
    private var depth = 0

    init(url: URL) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close_v2(handle)
            throw SQLiteError(message: message)
        }
        sqlite3_busy_timeout(handle, 5000)
        _ = try query("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=FULL")
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    private func fail() -> SQLiteError {
        SQLiteError(message: String(cString: sqlite3_errmsg(handle)))
    }

    private func prepare(_ sql: String, _ params: [SQLValue]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw fail()
        }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in params.enumerated() {
            let position = Int32(index + 1)
            let code: Int32
            switch value {
            case .text(let text): code = sqlite3_bind_text(statement, position, text, -1, transient)
            case .int(let number): code = sqlite3_bind_int64(statement, position, number)
            case .null: code = sqlite3_bind_null(statement, position)
            }
            guard code == SQLITE_OK else {
                sqlite3_finalize(statement)
                throw fail()
            }
        }
        return statement
    }

    /// Runs a statement and returns the number of rows it changed.
    @discardableResult
    func execute(_ sql: String, _ params: [SQLValue] = []) throws -> Int {
        let statement = try prepare(sql, params)
        defer { sqlite3_finalize(statement) }
        let code = sqlite3_step(statement)
        guard code == SQLITE_DONE || code == SQLITE_ROW else { throw fail() }
        return Int(sqlite3_changes(handle))
    }

    func query(_ sql: String, _ params: [SQLValue] = []) throws -> [[SQLValue]] {
        let statement = try prepare(sql, params)
        defer { sqlite3_finalize(statement) }
        var rows: [[SQLValue]] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { break }
            guard code == SQLITE_ROW else { throw fail() }
            var row: [SQLValue] = []
            for column in 0..<sqlite3_column_count(statement) {
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER: row.append(.int(sqlite3_column_int64(statement, column)))
                case SQLITE_TEXT: row.append(.text(String(cString: sqlite3_column_text(statement, column))))
                default: row.append(.null)
                }
            }
            rows.append(row)
        }
        return rows
    }

    /// Runs `body` in one transaction: everything commits, or the error rolls
    /// it all back. Nested calls join the outer transaction.
    func transaction<T>(_ body: () throws -> T) throws -> T {
        if depth > 0 { return try body() }
        try execute("BEGIN IMMEDIATE")
        depth += 1
        defer { depth -= 1 }
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            _ = try? execute("ROLLBACK")
            throw error
        }
    }

    func setUserVersion(_ version: Int) throws {
        try execute("PRAGMA user_version = \(version)")
    }
}
