package `in`.beyondrep.wear.core

import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths

/** Reads the shared contract files from disk, like FixtureLoader.swift. */
object FixtureLoader {
    fun repoRoot(): Path {
        var dir: Path? = Paths.get(System.getProperty("user.dir")).toAbsolutePath()
        while (dir != null) {
            if (Files.isDirectory(dir.resolve("contracts"))) return dir
            dir = dir.parent
        }
        error("contracts directory not found above ${System.getProperty("user.dir")}")
    }

    fun text(relative: String): String = Files.readString(repoRoot().resolve(relative))

    fun files(relativeDir: String): List<Path> =
        Files.list(repoRoot().resolve(relativeDir)).use { stream ->
            stream.filter { it.fileName.toString().endsWith(".json") }
                .sorted(compareBy { it.fileName.toString() })
                .toList()
        }
}
