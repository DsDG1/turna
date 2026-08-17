package me.dsdogs.turna.anki.reviewer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PresentAckCoordinatorTest {
    @Test
    fun rapidQuestionAnswerQuestionSupersedesAndKeepsNewestHeight() {
        val ack = PresentAckCoordinator()
        val completed = mutableListOf<PresentAckCoordinator.PresentResult>()

        val q1 = ack.begin(1, "question") { completed.add(it) }
        val a2 = ack.begin(2, "answer") { completed.add(it) }
        val q3 = ack.begin(3, "question") { completed.add(it) }

        assertEquals(2, completed.size)
        assertTrue(completed.all { it.code == PresentAckCoordinator.CODE_SUPERSEDED })
        assertFalse(completed.any { it.ok })
        assertEquals(1L, completed[0].generation)
        assertEquals(2L, completed[1].generation)
        assertTrue(ack.isActive(q3.id))
        assertFalse(ack.isActive(q1.id))
        assertFalse(ack.isActive(a2.id))

        assertNull(ack.complete(q1.id, PresentAckCoordinator.PresentResult(ok = true, generation = 1, height = 11.0)))
        assertNull(ack.complete(a2.id, PresentAckCoordinator.PresentResult(ok = true, generation = 2, height = 22.0)))
        assertFalse(ack.shouldPublishHeight(1, 11.0))
        assertFalse(ack.shouldPublishHeight(2, 22.0))

        val latest = ack.complete(
            q3.id,
            PresentAckCoordinator.PresentResult(
                ok = true,
                generation = 3,
                side = "question",
                height = 33.0,
            ),
        )
        assertTrue(latest!!.ok)
        assertEquals(33.0, latest.height)
        assertEquals(33.0, ack.lastHeight, 0.0)
        assertFalse(ack.shouldPublishHeight(1, 99.0))
        assertEquals(33.0, ack.lastHeight, 0.0)
    }

    @Test
    fun completeUsesCapturedRequestId() {
        val ack = PresentAckCoordinator()
        val first = ack.begin(4, "answer") {}
        assertTrue(ack.shouldPublishHeight(4, 40.0))
        val done = ack.complete(
            first.id,
            PresentAckCoordinator.PresentResult(ok = true, generation = 4, side = "answer", height = 40.0),
        )
        assertEquals("answer", done!!.side)
        assertEquals(4L, done.generation)
        assertNull(ack.activeRequest())
    }
}
