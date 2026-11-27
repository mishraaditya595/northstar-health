package `in`.beyondrep.wear.core.store

/** A value bound to or read from a SQLite statement (SQLValue in SQLiteDatabase.swift). */
sealed interface SqlValue {
    data class Text(val v: String) : SqlValue
    data class Int64(val v: Long) : SqlValue
    data object Null : SqlValue
}

/**
 * The small SQLite surface the journal needs, so the core has no `android.*` import. The JVM tests
 * implement it with sqlite-jdbc, the watch app with `android.database.sqlite`. Implementations own
 * one connection, enable write-ahead logging with FULL synchronous mode and are not thread-safe:
 * one serial owner makes every call.
 */
interface SqlDatabase {
    /** Runs a statement and returns the number of rows it changed. */
    fun execute(sql: String, args: List<SqlValue> = emptyList()): Int

    fun query(sql: String, args: List<SqlValue> = emptyList()): List<List<SqlValue>>

    /**
     * Runs `block` in one transaction: everything commits, or the exception rolls it all back.
     * Nested calls join the outer transaction (the `depth` rule of SQLiteDatabase.swift).
     */
    fun <T> transaction(block: () -> T): T
}
