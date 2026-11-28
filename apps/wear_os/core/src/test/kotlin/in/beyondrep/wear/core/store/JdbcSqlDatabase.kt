package `in`.beyondrep.wear.core.store

import java.nio.file.Path
import java.sql.Connection
import java.sql.DriverManager

/**
 * A SqlDatabase over xerial `sqlite-jdbc`, for the JVM tests. It mirrors SQLiteDatabase.swift:
 * one connection, WAL, FULL synchronous, explicit transactions that nested calls join.
 */
class JdbcSqlDatabase(path: Path) : SqlDatabase, AutoCloseable {
    private val connection: Connection = DriverManager.getConnection("jdbc:sqlite:$path")
    private var depth = 0

    init {
        connection.createStatement().use {
            it.execute("PRAGMA busy_timeout=5000")
            it.executeQuery("PRAGMA journal_mode=WAL").use { rs ->
                check(rs.next() && rs.getString(1).lowercase() == "wal") { "could not enable write-ahead logging" }
            }
            it.execute("PRAGMA synchronous=FULL")
        }
    }

    private fun bind(statement: java.sql.PreparedStatement, args: List<SqlValue>) {
        args.forEachIndexed { index, value ->
            when (value) {
                is SqlValue.Text -> statement.setString(index + 1, value.v)
                is SqlValue.Int64 -> statement.setLong(index + 1, value.v)
                SqlValue.Null -> statement.setNull(index + 1, java.sql.Types.NULL)
            }
        }
    }

    override fun execute(sql: String, args: List<SqlValue>): Int =
        connection.prepareStatement(sql).use { statement ->
            bind(statement, args)
            // PRAGMA statements may return a row, so use `execute` and read the change count after.
            statement.execute()
            connection.createStatement().use { it.executeQuery("SELECT changes()").use { rs -> rs.next(); rs.getInt(1) } }
        }

    override fun query(sql: String, args: List<SqlValue>): List<List<SqlValue>> =
        connection.prepareStatement(sql).use { statement ->
            bind(statement, args)
            statement.executeQuery().use { rs ->
                val rows = mutableListOf<List<SqlValue>>()
                val columns = rs.metaData.columnCount
                while (rs.next()) {
                    rows.add(
                        (1..columns).map { c ->
                            when (val v = rs.getObject(c)) {
                                null -> SqlValue.Null
                                is Number -> SqlValue.Int64(v.toLong())
                                else -> SqlValue.Text(v.toString())
                            }
                        },
                    )
                }
                rows
            }
        }

    override fun <T> transaction(block: () -> T): T {
        if (depth > 0) return block()
        execute("BEGIN IMMEDIATE")
        depth += 1
        try {
            val result = block()
            execute("COMMIT")
            return result
        } catch (e: Throwable) {
            runCatching { execute("ROLLBACK") }
            throw e
        } finally {
            depth -= 1
        }
    }

    override fun close() = connection.close()
}

/**
 * Wraps a database so a test can make one statement throw, before it runs (`failBefore`) or after
 * it ran (`failAfter`), to prove the surrounding transaction rolls back.
 */
class FailingSqlDatabase(private val delegate: SqlDatabase) : SqlDatabase {
    var failBefore: ((String, List<SqlValue>) -> Boolean)? = null
    var failAfter: ((String, List<SqlValue>) -> Boolean)? = null

    override fun execute(sql: String, args: List<SqlValue>): Int {
        if (failBefore?.invoke(sql, args) == true) error("injected failure before: $sql")
        val changed = delegate.execute(sql, args)
        if (failAfter?.invoke(sql, args) == true) error("injected failure after: $sql")
        return changed
    }

    override fun query(sql: String, args: List<SqlValue>) = delegate.query(sql, args)
    override fun <T> transaction(block: () -> T): T = delegate.transaction(block)
}
