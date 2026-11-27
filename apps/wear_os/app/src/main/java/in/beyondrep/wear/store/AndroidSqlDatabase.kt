package `in`.beyondrep.wear.store

import android.content.Context
import android.database.DatabaseUtils
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import `in`.beyondrep.wear.core.store.SqlDatabase
import `in`.beyondrep.wear.core.store.SqlValue

/**
 * The watch's [SqlDatabase] over `android.database.sqlite`. The journal creates its own schema and
 * sets `user_version`, so the helper creates nothing. Write-ahead logging and FULL synchronous mode
 * match the JVM test adapter and the Swift journal. Not thread-safe: one serial owner makes every
 * call. Not used by any screen yet (stage 2); verified by `:app:assembleDebug` on CI.
 */
class AndroidSqlDatabase(context: Context, name: String = "beyondrep_watch.db") : SqlDatabase {
    private val helper = object : SQLiteOpenHelper(context.applicationContext, name, null, 1) {
        override fun onConfigure(db: SQLiteDatabase) {
            db.enableWriteAheadLogging()
        }

        override fun onCreate(db: SQLiteDatabase) = Unit

        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

        override fun onOpen(db: SQLiteDatabase) {
            db.execSQL("PRAGMA synchronous=FULL")
        }
    }
    private val db: SQLiteDatabase get() = helper.writableDatabase

    private fun bindArgs(args: List<SqlValue>): Array<Any?> =
        Array(args.size) { i ->
            when (val v = args[i]) {
                is SqlValue.Text -> v.v
                is SqlValue.Int64 -> v.v
                SqlValue.Null -> null
            }
        }

    override fun execute(sql: String, args: List<SqlValue>): Int {
        db.execSQL(sql, bindArgs(args))
        return DatabaseUtils.longForQuery(db, "SELECT changes()", null).toInt()
    }

    override fun query(sql: String, args: List<SqlValue>): List<List<SqlValue>> {
        // rawQuery binds every argument as text, which SQLite compares correctly against the
        // affinity of the journal's columns; integers are passed through their decimal form.
        val strings = Array(args.size) { i ->
            when (val v = args[i]) {
                is SqlValue.Text -> v.v
                is SqlValue.Int64 -> v.v.toString()
                SqlValue.Null -> null
            }
        }
        db.rawQuery(sql, strings).use { cursor ->
            val rows = mutableListOf<List<SqlValue>>()
            while (cursor.moveToNext()) {
                rows.add(
                    (0 until cursor.columnCount).map { c ->
                        when (cursor.getType(c)) {
                            android.database.Cursor.FIELD_TYPE_NULL -> SqlValue.Null
                            android.database.Cursor.FIELD_TYPE_INTEGER -> SqlValue.Int64(cursor.getLong(c))
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
        val database = db
        database.beginTransaction()
        depth += 1
        try {
            val result = block()
            database.setTransactionSuccessful()
            return result
        } finally {
            depth -= 1
            database.endTransaction()
        }
    }
}
