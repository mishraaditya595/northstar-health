package `in`.beyondrep.wear.store

import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteCursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteProgram
import `in`.beyondrep.wear.core.store.SqlDatabase
import `in`.beyondrep.wear.core.store.SqlValue

/**
 * The watch's [SqlDatabase] over `android.database.sqlite`. The journal creates its own schema and
 * owns `user_version`, so the database is opened directly (no `SQLiteOpenHelper`, which would
 * version the file and throw on a downgrade). Write-ahead logging and FULL synchronous mode are set
 * per connection through `OpenParams`, matching the JVM test adapter and the Swift journal.
 * Statements bind typed values; a DML statement reads its row count from the same statement.
 * Not thread-safe: one serial owner makes every call. Not used by any screen yet (stage 2);
 * verified by `:app:assembleDebug` on CI.
 */
class AndroidSqlDatabase(context: Context, name: String = "beyondrep_watch.db") : SqlDatabase {
    private val db: SQLiteDatabase

    init {
        val file = context.applicationContext.getDatabasePath(name)
        file.parentFile?.mkdirs()
        val params = SQLiteDatabase.OpenParams.Builder()
            .addOpenFlags(SQLiteDatabase.CREATE_IF_NECESSARY)
            .setJournalMode("WAL")
            .setSynchronousMode("FULL")
            .build()
        db = SQLiteDatabase.openDatabase(file, params)
    }

    private fun bind(program: SQLiteProgram, args: List<SqlValue>) {
        args.forEachIndexed { i, value ->
            when (value) {
                is SqlValue.Text -> program.bindString(i + 1, value.v)
                is SqlValue.Int64 -> program.bindLong(i + 1, value.v)
                SqlValue.Null -> program.bindNull(i + 1)
            }
        }
    }

    private fun isSchemaOrPragma(sql: String): Boolean {
        val head = sql.trimStart().uppercase()
        return listOf("CREATE", "PRAGMA", "DROP", "ALTER").any { head.startsWith(it) }
    }

    override fun execute(sql: String, args: List<SqlValue>): Int {
        if (isSchemaOrPragma(sql)) {
            db.execSQL(sql)
            return 0
        }
        db.compileStatement(sql).use { statement ->
            bind(statement, args)
            return statement.executeUpdateDelete()
        }
    }

    override fun query(sql: String, args: List<SqlValue>): List<List<SqlValue>> {
        // Typed binding through a cursor factory: rawQuery would bind every argument as text and
        // cannot bind NULL.
        val factory = SQLiteDatabase.CursorFactory { _, driver, editTable, query ->
            bind(query, args)
            SQLiteCursor(driver, editTable, query)
        }
        db.rawQueryWithFactory(factory, sql, null, null).use { cursor ->
            val rows = mutableListOf<List<SqlValue>>()
            while (cursor.moveToNext()) {
                rows.add(
                    (0 until cursor.columnCount).map { c ->
                        when (cursor.getType(c)) {
                            Cursor.FIELD_TYPE_NULL -> SqlValue.Null
                            Cursor.FIELD_TYPE_INTEGER -> SqlValue.Int64(cursor.getLong(c))
                            // Like the JDBC test adapter: any number becomes an Int64.
                            Cursor.FIELD_TYPE_FLOAT -> SqlValue.Int64(cursor.getDouble(c).toLong())
                            else -> SqlValue.Text(cursor.getString(c))
                        }
                    },
                )
            }
            return rows
        }
    }

    private var depth = 0

    override fun <T> transaction(block: () -> T): T {
        if (depth > 0) return block()
        db.beginTransaction()
        depth += 1
        try {
            val result = block()
            db.setTransactionSuccessful()
            return result
        } finally {
            depth -= 1
            db.endTransaction()
        }
    }
}
