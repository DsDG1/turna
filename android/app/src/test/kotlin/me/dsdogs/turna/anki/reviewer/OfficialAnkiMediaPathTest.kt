package me.dsdogs.turna.anki.reviewer

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class OfficialAnkiMediaPathTest {
    @Test
    fun sharedVectorsMatchDartAllowDeny() {
        val file = locateVectors()
        val json = JSONObject(file.readText())
        val vectors = json.getJSONArray("vectors")
        assertTrue(vectors.length() >= 40)
        for (i in 0 until vectors.length()) {
            val item = vectors.getJSONObject(i)
            val encoded = item.getString("encodedName")
            val allowed = item.getBoolean("allowed")
            val decision = OfficialAnkiMediaPath.classifyEncodedName(encoded)
            assertEquals(
                "${item.getString("id")} encoded=$encoded reason=${decision.reason}",
                allowed,
                decision.allowed,
            )
            if (allowed) {
                assertEquals(item.getString("expectedName"), decision.filename)
            }
        }
    }

    @Test
    fun fooDotDotBarIsNotRejectedAsTraversal() {
        val decision = OfficialAnkiMediaPath.classifyDecodedName("foo..bar.png")
        assertTrue(decision.allowed)
        assertEquals("foo..bar.png", decision.filename)
    }

    @Test
    fun decodeOnceDoesNotDecodeTwice() {
        assertEquals("%2e%2e%2fsecret", OfficialAnkiMediaPath.decodeOnce("%252e%252e%252fsecret"))
        assertEquals(false, OfficialAnkiMediaPath.classifyEncodedName("%252e%252e%252fsecret").allowed)
    }

    private fun locateVectors(): File {
        val candidates = listOf(
            File("test/fixtures/anki_official/media_path_vectors.json"),
            File("../test/fixtures/anki_official/media_path_vectors.json"),
            File("../../test/fixtures/anki_official/media_path_vectors.json"),
            File("../../../test/fixtures/anki_official/media_path_vectors.json"),
        )
        return candidates.firstOrNull { it.isFile }
            ?: throw AssertionError("missing media_path_vectors.json from ${File(".").absolutePath}")
    }
}
