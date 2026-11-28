package `in`.beyondrep.wear.core.store

import java.nio.file.Files
import java.nio.file.Path

/** Temp-file SQLite journals for a test class: call `close()` from an `@AfterEach`. */
class JournalFiles {
    val dir: Path = Files.createTempDirectory("journal")
    private val opened = mutableListOf<JdbcSqlDatabase>()

    fun db(name: String = "journal.sqlite"): JdbcSqlDatabase = JdbcSqlDatabase(dir.resolve(name)).also { opened.add(it) }

    fun close() {
        opened.forEach { runCatching { it.close() } }
        dir.toFile().deleteRecursively()
    }
}
