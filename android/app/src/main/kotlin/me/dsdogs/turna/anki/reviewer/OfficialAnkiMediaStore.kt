package me.dsdogs.turna.anki.reviewer

import java.io.File

object OfficialAnkiMediaStore {
    fun resolveMediaFile(mediaRoot: File, rawName: String): File? {
        val decision = OfficialAnkiMediaPath.classifyDecodedName(rawName)
        if (!decision.allowed || decision.filename == null) return null
        val root = mediaRoot.canonicalFile
        val candidate = File(mediaRoot, decision.filename)
        if (!candidate.exists()) return null
        val resolved = candidate.canonicalFile
        val rootPath = root.path.let { if (it.endsWith(File.separator)) it else it + File.separator }
        if (resolved != root && !resolved.path.startsWith(rootPath)) return null
        if (resolved.isDirectory || candidate.isDirectory) return null
        if (isEscapingSymlink(candidate, rootPath)) return null
        return resolved
    }

    private fun isEscapingSymlink(candidate: File, rootPath: String): Boolean {
        val parent = candidate.parentFile ?: return true
        if (parent.canonicalPath != parent.absoluteFile.canonicalPath &&
            !parent.canonicalPath.startsWith(rootPath)
        ) {
            return true
        }
        return candidate.canonicalPath != candidate.absoluteFile.canonicalPath &&
            !candidate.canonicalPath.startsWith(rootPath)
    }
}
