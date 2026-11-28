package `in`.beyondrep.wear.core.session

enum class SessionError { INVALID_TRANSITION, UNKNOWN_SET, INVALID_COMMAND }

/** Thrown by the session machine and the builders; the Kotlin form of Swift's `SessionError`. */
class SessionException(val error: SessionError) : Exception(error.name)
