package me.dsdogs.turna.anki.reviewer

import java.nio.charset.Charset
import java.nio.charset.StandardCharsets

object OfficialAnkiMediaPath {
    const val ORIGIN_HOST = "anki.local"
    const val ASSET_PREFIX = "/assets/"
    const val MEDIA_PREFIX = "/media/"

    data class NameDecision(val allowed: Boolean, val filename: String? = null, val reason: String? = null)
    data class RequestTarget(
        val allowed: Boolean,
        val assetName: String? = null,
        val mediaName: String? = null,
        val reason: String? = null,
    )

    fun decodeOnce(encoded: String): String? {
        val bytes = ArrayList<Int>(encoded.length)
        var i = 0
        while (i < encoded.length) {
            val ch = encoded[i]
            if (ch.code == 0) return null
            if (ch != '%') {
                bytes.add(ch.code and 0xff)
                i += 1
                continue
            }
            if (i + 2 >= encoded.length) return null
            val hex = encoded.substring(i + 1, i + 3)
            val value = hex.toIntOrNull(16) ?: return null
            if (!hex.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }) return null
            bytes.add(value)
            i += 3
        }
        if (bytes.any { it == 0 }) return null
        val raw = ByteArray(bytes.size) { bytes[it].toByte() }
        return try {
            String(raw, StandardCharsets.UTF_8)
        } catch (_: Exception) {
            String(raw, Charset.forName("ISO-8859-1"))
        }
    }

    fun classifyDecodedName(decoded: String): NameDecision {
        if (decoded.isEmpty() || decoded.contains('\u0000')) {
            return NameDecision(false, reason = "empty_or_nul")
        }
        if (decoded.contains('/') || decoded.contains('\\')) {
            return NameDecision(false, reason = "separator")
        }
        if (decoded == "." || decoded == "..") {
            return NameDecision(false, reason = "dotdot")
        }
        if (decoded.startsWith("/") || Regex("^[A-Za-z]:").containsMatchIn(decoded)) {
            return NameDecision(false, reason = "absolute")
        }
        if (hasResidualEncodedTraversal(decoded)) {
            return NameDecision(false, reason = "double_encoding")
        }
        return NameDecision(true, filename = decoded)
    }

    fun classifyEncodedName(encodedName: String): NameDecision {
        if (encodedName.contains('/') || encodedName.contains('\\')) {
            return NameDecision(false, reason = "separator")
        }
        val decoded = decodeOnce(encodedName) ?: return NameDecision(false, reason = "malformed_percent")
        return classifyDecodedName(decoded)
    }

    fun classifyEncodedPath(encodedPath: String): RequestTarget {
        if (encodedPath.startsWith(ASSET_PREFIX)) {
            val name = encodedPath.removePrefix(ASSET_PREFIX)
            if (!isSafeAssetName(name)) return RequestTarget(false, reason = "asset_name")
            return RequestTarget(true, assetName = name)
        }
        if (!encodedPath.startsWith(MEDIA_PREFIX)) {
            return RequestTarget(false, reason = "prefix")
        }
        val decision = classifyEncodedName(encodedPath.removePrefix(MEDIA_PREFIX))
        if (!decision.allowed || decision.filename == null) {
            return RequestTarget(false, reason = decision.reason ?: "media_name")
        }
        return RequestTarget(true, mediaName = decision.filename)
    }

    fun isSafeAssetName(name: String): Boolean {
        if (name.isEmpty() || name.startsWith("/")) return false
        if (name.split("/").contains("..")) return false
        return name.matches(Regex("^[A-Za-z0-9._/-]+$")) && !name.contains("//")
    }

    private fun hasResidualEncodedTraversal(decoded: String): Boolean {
        val lower = decoded.lowercase()
        return lower.contains("%2f") ||
            lower.contains("%5c") ||
            lower.contains("%00") ||
            lower.contains("%2e%2e")
    }

    fun originAllowed(scheme: String?, host: String?, port: Int): Boolean {
        if (scheme != "https") return false
        if (host != ORIGIN_HOST) return false
        if (port != -1 && port != 443) return false
        return true
    }
}
