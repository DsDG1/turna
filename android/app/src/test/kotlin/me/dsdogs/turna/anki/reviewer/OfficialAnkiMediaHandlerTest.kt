package me.dsdogs.turna.anki.reviewer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import java.io.File
import java.nio.file.Files

class OfficialAnkiMediaHandlerTest {
    @Test
    fun resolveMediaFileAllowsSingleSegmentAndRejectsTraversal() {
        val root = Files.createTempDirectory("turna-media-kt").toFile()
        try {
            File(root, "foo..bar.png").writeBytes(byteArrayOf(1))
            File(root, "hello world.png").writeBytes(byteArrayOf(2))
            assertNotNull(OfficialAnkiMediaStore.resolveMediaFile(root, "foo..bar.png"))
            assertNotNull(OfficialAnkiMediaStore.resolveMediaFile(root, "hello world.png"))
            assertNull(OfficialAnkiMediaStore.resolveMediaFile(root, "../secret"))
            assertNull(OfficialAnkiMediaStore.resolveMediaFile(root, "a/b.png"))
            assertNull(OfficialAnkiMediaStore.resolveMediaFile(root, ".."))
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun unknownMimeGetsNosniffPolicy() {
        assertEquals("application/octet-stream", OfficialAnkiMime.mimeForName("x.bin"))
        assertEquals(null, OfficialAnkiMime.encodingForMime("application/octet-stream"))
        assertFalse(OfficialAnkiMediaPath.originAllowed("http", "anki.local", 443))
        assertFalse(OfficialAnkiMediaPath.originAllowed("https", "evil.example", 443))
    }
}
