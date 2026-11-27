package `in`.beyondrep.wear.core.contracts

import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlin.math.abs
import kotlin.math.floor

/**
 * A contract violation. `code` is one of `unsupported_version`, `unknown_type`, `unknown_key`,
 * `missing_field`, `invalid_value` (the same codes as Dart and Swift).
 */
class ContractException(val code: String) : Exception(code)

/**
 * An object whose keys were checked against a required and an optional set (port of
 * StrictJSON.swift). Plain decoding ignores unknown keys, which the schemas forbid, so the
 * codecs read through this type.
 */
internal class StrictObject(raw: JsonElement?, required: Set<String>, optional: Set<String> = emptySet()) {
    val dict: JsonObject

    init {
        val obj = raw as? JsonObject ?: throw ContractException("invalid_value")
        for (key in obj.keys) {
            if (key !in required && key !in optional) throw ContractException("unknown_key")
        }
        for (key in required) {
            if (key !in obj) throw ContractException("missing_field")
        }
        dict = obj
    }

    fun has(key: String): Boolean = key in dict

    fun string(key: String, min: Int = 1, max: Int? = null, pattern: Regex? = null): String {
        val p = dict[key] as? JsonPrimitive
        if (p == null || !p.isString) throw ContractException("invalid_value")
        val value = p.content
        val length = value.codePointCount(0, value.length) // JSON Schema counts code points
        if (length < min || (max != null && length > max)) throw ContractException("invalid_value")
        // `matches` needs the whole string, so a trailing newline never slips through.
        if (pattern != null && !pattern.matches(value)) throw ContractException("invalid_value")
        return value
    }

    fun optionalString(key: String, min: Int = 1, max: Int? = null): String? =
        if (has(key)) string(key, min, max) else null

    fun uuid(key: String): String = string(key, pattern = UUID)

    fun dateTime(key: String): String {
        val value = string(key, pattern = DATE_TIME)
        // The pattern allows 2026-02-30, so check each part (same as Swift and Dart).
        val d = value.map { it.code - 48 }
        fun num(range: IntRange): Int = range.fold(0) { acc, i -> acc * 10 + d[i] }
        val year = num(0..3)
        val month = num(5..6)
        val day = num(8..9)
        val leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        val days = intArrayOf(31, if (leap) 29 else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
        var valid = month in 1..12 && day >= 1 && day <= days[month - 1] &&
            num(11..12) <= 23 && num(14..15) <= 59 && num(17..18) <= 59
        val last = value.last()
        if (last != 'Z' && last != 'z') {
            val n = d.size
            valid = valid && num((n - 5)..(n - 4)) <= 23 && num((n - 2)..(n - 1)) <= 59
        }
        if (!valid) throw ContractException("invalid_value")
        return value
    }

    fun accountKey(): String = string("account_key", pattern = ACCOUNT_KEY)

    fun localDate(key: String): String = string(key, pattern = LOCAL_DATE)

    fun oneOf(key: String, allowed: Set<String>): String {
        val p = dict[key] as? JsonPrimitive
        if (p == null || !p.isString || p.content !in allowed) throw ContractException("invalid_value")
        return p.content
    }

    /**
     * A whole number. Like StrictJSON.int, `10.0` and `1e1` are whole numbers and pass, `10.5`,
     * strings and booleans do not. Unlike Swift (64-bit Int, up to 9e15) a value outside the
     * Kotlin Int range is rejected.
     */
    fun int(key: String, min: Int = 0, max: Int? = null): Int {
        val double = number(key)
        if (double != floor(double) || abs(double) >= 9e15) throw ContractException("invalid_value")
        if (double > Int.MAX_VALUE || double < Int.MIN_VALUE) throw ContractException("invalid_value")
        val value = double.toInt()
        if (value < min || (max != null && value > max)) throw ContractException("invalid_value")
        return value
    }

    fun optionalInt(key: String, min: Int = 0, max: Int? = null): Int? =
        if (has(key)) int(key, min, max) else null

    fun bool(key: String): Boolean {
        val p = dict[key] as? JsonPrimitive
        if (p == null || p.isString) throw ContractException("invalid_value")
        return when (p.content) {
            "true" -> true
            "false" -> false
            else -> throw ContractException("invalid_value")
        }
    }

    /** A number from 1 to 10 in half steps. */
    fun rpe(key: String): Double {
        val value = number(key)
        if (!(value >= 1 && value <= 10 && value * 2 == floor(value * 2))) throw ContractException("invalid_value")
        return value
    }

    fun optionalRpe(key: String): Double? = if (has(key)) rpe(key) else null

    fun obj(key: String, required: Set<String>, optional: Set<String> = emptySet()): StrictObject =
        StrictObject(dict[key], required, optional)

    fun array(key: String, max: Int? = null): JsonArray {
        val value = dict[key] as? JsonArray ?: throw ContractException("invalid_value")
        if (max != null && value.size > max) throw ContractException("invalid_value")
        return value
    }

    /** A JSON number as a Double; strings, booleans and null are `invalid_value`. */
    private fun number(key: String): Double = numberOf(dict[key])

    companion object {
        private val UUID = Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
        private val DATE_TIME =
            Regex("[0-9]{4}-[0-9]{2}-[0-9]{2}[Tt][0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?([Zz]|[+-][0-9]{2}:[0-9]{2})")
        private val ACCOUNT_KEY = Regex("[0-9a-f]{64}")
        private val LOCAL_DATE = Regex("[0-9]{4}-[0-9]{2}-[0-9]{2}")

        fun numberOf(element: JsonElement?): Double {
            val p = element as? JsonPrimitive
            if (p == null || p.isString || p.content == "true" || p.content == "false" || p.content == "null") {
                throw ContractException("invalid_value")
            }
            return p.content.toDoubleOrNull() ?: throw ContractException("invalid_value")
        }

        /** Parses `text` as a JSON object; anything else is `invalid_value`. */
        fun parse(text: String): JsonObject {
            val element = try {
                Json.parseToJsonElement(text)
            } catch (_: SerializationException) {
                throw ContractException("invalid_value")
            } catch (_: IllegalArgumentException) {
                throw ContractException("invalid_value")
            }
            return element as? JsonObject ?: throw ContractException("invalid_value")
        }

        /** Serialises with keys sorted at every level, like `JSONSerialization` `.sortedKeys`. */
        fun encode(element: JsonElement): String = sorted(element).toString()

        private fun sorted(element: JsonElement): JsonElement = when (element) {
            is JsonObject -> JsonObject(element.toSortedMap().mapValues { sorted(it.value) })
            is JsonArray -> JsonArray(element.map { sorted(it) })
            else -> element
        }

        /** An Int as a JSON number. */
        fun number(value: Int): JsonPrimitive = JsonPrimitive(value)

        /** A Double as a JSON number, written as an integer when it is whole (8.0 becomes 8). */
        fun number(value: Double): JsonPrimitive =
            if (value == floor(value) && abs(value) < 9e15) JsonPrimitive(value.toLong()) else JsonPrimitive(value)
    }
}
