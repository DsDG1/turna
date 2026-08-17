package me.dsdogs.turna.anki.reviewer

data class OfficialAnkiHttpRange(
    val satisfiable: Boolean,
    val start: Long,
    val end: Long,
    val length: Long,
    val status: Int,
) {
    val contentLength: Long
        get() = if (satisfiable && end >= start) end - start + 1 else 0

    val contentRange: String
        get() = if (satisfiable) "bytes $start-$end/$length" else "bytes */$length"

    companion object {
        fun unsatisfiable(length: Long) = OfficialAnkiHttpRange(false, 0, -1, length, 416)

        fun full(length: Long) = OfficialAnkiHttpRange(
            true,
            0,
            if (length <= 0) -1 else length - 1,
            length,
            200,
        )

        fun parse(header: String?, length: Long): OfficialAnkiHttpRange {
            if (header.isNullOrBlank()) return full(length)
            val trimmed = header.trim()
            if (!trimmed.startsWith("bytes=", ignoreCase = true)) {
                return unsatisfiable(length)
            }
            val spec = trimmed.substring(6).trim()
            if (spec.isEmpty() || spec.contains(',')) return unsatisfiable(length)
            val dash = spec.indexOf('-')
            if (dash < 0) return unsatisfiable(length)
            val left = spec.substring(0, dash).trim()
            val right = spec.substring(dash + 1).trim()
            if (length <= 0) return unsatisfiable(length)
            if (left.isEmpty() && right.isEmpty()) return unsatisfiable(length)
            if (left.isEmpty()) {
                val suffix = right.toLongOrNull() ?: return unsatisfiable(length)
                if (suffix <= 0) return unsatisfiable(length)
                val start = if (length > suffix) length - suffix else 0
                return OfficialAnkiHttpRange(true, start, length - 1, length, 206)
            }
            val start = left.toLongOrNull() ?: return unsatisfiable(length)
            if (start < 0 || start >= length) return unsatisfiable(length)
            val end = if (right.isEmpty()) {
                length - 1
            } else {
                right.toLongOrNull() ?: return unsatisfiable(length)
            }
            if (end < start) return unsatisfiable(length)
            val clamped = if (end >= length) length - 1 else end
            return OfficialAnkiHttpRange(true, start, clamped, length, 206)
        }
    }
}
