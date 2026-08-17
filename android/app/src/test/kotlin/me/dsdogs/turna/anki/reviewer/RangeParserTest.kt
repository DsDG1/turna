package me.dsdogs.turna.anki.reviewer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream

class RangeParserTest {
    @Test
    fun parsesSingleRangesAndRejectsMultiRange() {
        val r1 = OfficialAnkiHttpRange.parse("bytes=0-99", 1000)
        assertTrue(r1.satisfiable)
        assertEquals(0L, r1.start)
        assertEquals(99L, r1.end)
        assertEquals(100L, r1.contentLength)
        assertEquals("bytes 0-99/1000", r1.contentRange)

        val open = OfficialAnkiHttpRange.parse("bytes=100-", 1000)
        assertEquals(100L, open.start)
        assertEquals(999L, open.end)

        val suffix = OfficialAnkiHttpRange.parse("bytes=-500", 1000)
        assertEquals(500L, suffix.start)
        assertEquals(500L, suffix.contentLength)

        assertFalse(OfficialAnkiHttpRange.parse("bytes=0-99", 0).satisfiable)
        assertEquals("bytes */0", OfficialAnkiHttpRange.parse("bytes=0-99", 0).contentRange)
        assertEquals(416, OfficialAnkiHttpRange.parse("bytes=50-40", 1000).status)
        assertEquals(416, OfficialAnkiHttpRange.parse("bytes=0-99,200-300", 1000).status)
        assertEquals(416, OfficialAnkiHttpRange.parse("bytes=1000-1001", 1000).status)
        assertEquals(1L, OfficialAnkiHttpRange.parse("bytes=0-0", 1).contentLength)
    }

    @Test
    fun limitedStreamDoesNotReturnPastEnd() {
        val data = ByteArray(1000) { it.toByte() }
        val range = OfficialAnkiHttpRange.parse("bytes=0-99", 1000)
        val stream = LimitedInputStream(ByteArrayInputStream(data), range.contentLength)
        val out = stream.readBytes()
        assertEquals(100, out.size)
        assertEquals(data.copyOfRange(0, 100).toList(), out.toList())
        assertEquals(-1, stream.read())
        stream.close()
    }

    @Test
    fun mimeEncodingIsNullForBinary() {
        assertEquals(null, OfficialAnkiMime.encodingForMime("image/png"))
        assertEquals(null, OfficialAnkiMime.encodingForMime("audio/mpeg"))
        assertEquals(null, OfficialAnkiMime.encodingForMime("font/woff2"))
        assertEquals("utf-8", OfficialAnkiMime.encodingForMime("text/css"))
        assertEquals("application/octet-stream", OfficialAnkiMime.mimeForName("x.bin"))
    }
}
