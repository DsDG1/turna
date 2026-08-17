package me.dsdogs.turna.anki.reviewer

object OfficialAnkiMime {
    fun mimeForName(name: String): String {
        val lower = name.lowercase()
        return when {
            lower.endsWith(".png") -> "image/png"
            lower.endsWith(".jpg") || lower.endsWith(".jpeg") -> "image/jpeg"
            lower.endsWith(".gif") -> "image/gif"
            lower.endsWith(".webp") -> "image/webp"
            lower.endsWith(".svg") -> "image/svg+xml"
            lower.endsWith(".mp3") -> "audio/mpeg"
            lower.endsWith(".ogg") -> "audio/ogg"
            lower.endsWith(".wav") -> "audio/wav"
            lower.endsWith(".m4a") -> "audio/mp4"
            lower.endsWith(".mp4") -> "video/mp4"
            lower.endsWith(".webm") -> "video/webm"
            lower.endsWith(".css") -> "text/css"
            lower.endsWith(".js") -> "text/javascript"
            lower.endsWith(".html") -> "text/html"
            lower.endsWith(".json") -> "application/json"
            lower.endsWith(".woff") -> "font/woff"
            lower.endsWith(".woff2") -> "font/woff2"
            lower.endsWith(".ttf") -> "font/ttf"
            lower.endsWith(".otf") -> "font/otf"
            else -> "application/octet-stream"
        }
    }

    fun encodingForMime(mime: String): String? {
        val base = mime.substringBefore(';').trim().lowercase()
        return if (base.startsWith("text/") ||
            base == "application/json" ||
            base == "application/javascript"
        ) {
            "utf-8"
        } else {
            null
        }
    }
}
