package me.dsdogs.turna.anki.reviewer

import androidx.test.ext.junit.rules.ActivityScenarioRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class OfficialAnkiReviewerFlipPathTest {
    @get:Rule
    val activityRule = ActivityScenarioRule(OfficialAnkiReviewerHarnessActivity::class.java)

    @Test
    fun entryGateFlipPath() {
        waitUntil("shell ready") { eval("window.OfficialReviewer && OfficialReviewer.ready() ? '1' : '0'") == "1" }

        present(
            cardId = 1,
            generation = 1,
            question = "<p id='q'>Q1</p>",
            answer = "<p id='a'>A1</p>",
            side = "question",
            ordinal = 0,
        )
        val q1 = waitRender(1, "question")
        assertEquals("question", q1.getString("side"))
        val qSnap = snapshot(1)
        assertEquals("question", qSnap.getString("side"))

        present(
            cardId = 1,
            generation = 2,
            question = "<p id='q'>Q1</p>",
            answer = "<p id='a'>A1-answer</p>",
            side = "answer",
            ordinal = 0,
        )
        val a1 = waitRender(2, "answer")
        assertEquals("answer", a1.getString("side"))
        val aSnap = snapshot(2)
        assertEquals("answer", aSnap.getString("side"))
        assertNotEquals(qSnap.getString("qaTextHash"), aSnap.getString("qaTextHash"))

        present(
            cardId = 2,
            generation = 3,
            question = "<p>Q2</p><img src='图片.png'>",
            answer = "<p>A2</p>",
            side = "question",
            ordinal = 1,
        )
        waitRender(3, "question")
        val bodySnap = snapshot(3)
        assertTrue(
            "expected card2 in ${bodySnap.optString("bodyClass")}",
            bodySnap.optString("bodyClass").contains("card2"),
        )
        val frameSeq = eval("String(window.__turnaFrameSeq || '')")
        assertTrue(frameSeq.toInt() >= 2)
        val media = bodySnap.optJSONArray("mediaUrls")?.toString() ?: ""
        assertTrue(media.contains("/media/") || media.contains("图片") || media.contains("%"))

        activityRule.scenario.onActivity { activity ->
            File(activity.mediaRoot, "图片.png").writeBytes(byteArrayOf(1, 2, 3, 4))
            val allowed = OfficialAnkiMediaPath.classifyEncodedPath("/media/%E5%9B%BE%E7%89%87.png")
            assertTrue(allowed.allowed)
            assertEquals("图片.png", allowed.mediaName)
            val https = OfficialAnkiMediaPath.originAllowed("https", "evil.example", 443)
            assertFalse(https)
            activity.webView.destroy()
            activity.webView.destroy()
        }
    }

    private fun present(
        cardId: Int,
        generation: Int,
        question: String,
        answer: String,
        side: String,
        ordinal: Int,
    ) {
        val payload = JSONObject()
            .put("cardId", cardId)
            .put("generation", generation)
            .put("questionDisplayHtml", question)
            .put("answerDisplayHtml", answer)
            .put("css", "")
            .put("theme", "day")
            .put("templateOrdinal", ordinal)
            .put("bodyClass", "card card${ordinal + 1}")
        eval(
            "(function(){ window.__turnaLastRender = null; " +
                "OfficialReviewer.present($payload, ${JSONObject.quote(side)}); return '1'; })()",
        )
    }

    private fun snapshot(generation: Int): JSONObject {
        eval("OfficialReviewerTest.snapshot($generation, null)")
        var last = JSONObject()
        waitUntil("testSnapshot gen=$generation") {
            val raw = eval(
                "(function(){ var a = window.__turnaLastSnapshot; return a ? JSON.stringify(a) : ''; })()",
            )
            if (raw.isEmpty()) return@waitUntil false
            last = JSONObject(raw)
            last.optString("type") == "testSnapshotResult" &&
                last.optInt("generation") == generation
        }
        return last
    }

    private fun waitRender(generation: Int, side: String): JSONObject {
        var last = JSONObject()
        waitUntil("renderComplete gen=$generation side=$side") {
            val raw = eval(
                "(function(){ var a = window.__turnaLastRender; return a ? JSON.stringify(a) : ''; })()",
            )
            if (raw.isEmpty()) return@waitUntil false
            last = JSONObject(raw)
            last.optString("type") == "renderComplete" &&
                last.optInt("generation") == generation &&
                last.optString("side") == side
        }
        return last
    }

    private fun waitUntil(label: String, check: () -> Boolean) {
        val deadline = System.currentTimeMillis() + 8_000
        while (System.currentTimeMillis() < deadline) {
            if (check()) return
            Thread.sleep(50)
        }
        throw AssertionError("timeout waiting for $label")
    }

    private fun eval(script: String): String {
        var value = ""
        val latch = CountDownLatch(1)
        activityRule.scenario.onActivity { activity ->
            activity.webView.post {
                activity.webView.evaluateJavascript(script) { result ->
                    value = unwrapJs(result)
                    latch.countDown()
                }
            }
        }
        assertTrue("evaluateJavascript timed out", latch.await(5, TimeUnit.SECONDS))
        return value
    }

    private fun unwrapJs(raw: String?): String {
        if (raw == null || raw == "null") return ""
        var text = raw
        if (text.startsWith("\"") && text.endsWith("\"")) {
            text = text.substring(1, text.length - 1).replace("\\\"", "\"")
        }
        return text
    }
}
