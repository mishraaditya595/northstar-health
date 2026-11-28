package `in`.beyondrep.wear.core

import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertTrue

class SmokeTest {
    @Test
    fun loadsAContractFixture() {
        val files = FixtureLoader.files("contracts/watch_link/v1/fixtures/valid")
        assertTrue(files.isNotEmpty())
        for (file in files) {
            Json.parseToJsonElement(FixtureLoader.text("contracts/watch_link/v1/fixtures/valid/${file.fileName}"))
        }
    }
}
