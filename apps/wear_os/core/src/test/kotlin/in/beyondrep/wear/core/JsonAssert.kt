package `in`.beyondrep.wear.core

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlin.test.fail

/**
 * Compares parsed JSON trees the way Swift compares NSDictionary: objects by key, arrays in
 * order, numbers by value (so 8 equals 8.0), strings and booleans exactly.
 */
object JsonAssert {
    fun equalTrees(a: JsonElement?, b: JsonElement?): Boolean {
        if (a is JsonObject && b is JsonObject) {
            return a.keys == b.keys && a.keys.all { equalTrees(a[it], b[it]) }
        }
        if (a is JsonArray && b is JsonArray) {
            return a.size == b.size && a.indices.all { equalTrees(a[it], b[it]) }
        }
        if (a is JsonPrimitive && b is JsonPrimitive) {
            if (a.isString || b.isString) return a.isString == b.isString && a.content == b.content
            val x = a.content.toBigDecimalOrNull()
            val y = b.content.toBigDecimalOrNull()
            if (x != null && y != null) return x.compareTo(y) == 0
            return a.content == b.content
        }
        return false
    }

    fun assertEqualTrees(expected: JsonElement?, actual: JsonElement?, label: String = "") {
        if (!equalTrees(expected, actual)) fail("$label\nexpected: $expected\nactual:   $actual")
    }
}

