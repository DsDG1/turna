package me.dsdogs.turna.anki.reviewer

object OfficialAnkiCsp {
    const val ORIGIN_HOST = "anki.local"
    const val SHELL_URL = "https://anki.local/assets/reviewer.html"
    const val VALUE =
        "default-src 'none'; " +
            "img-src https://anki.local data: blob:; " +
            "media-src https://anki.local data: blob:; " +
            "font-src https://anki.local data:; " +
            "style-src 'unsafe-inline' https://anki.local; " +
            "script-src 'unsafe-inline' https://anki.local; " +
            "connect-src 'none'; " +
            "frame-src https://anki.local; " +
            "object-src 'none'; " +
            "base-uri https://anki.local/media/; " +
            "form-action 'none';"

    fun isShellUrl(url: String?): Boolean {
        if (url == null) return false
        return url == SHELL_URL || url.startsWith("$SHELL_URL?")
    }
}
