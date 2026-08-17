package me.dsdogs.turna.anki.reviewer

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OfficialAnkiWebPolicyTest {
    @Test
    fun cspAllowsOnlyAnkiLocalCardFrame() {
        assertTrue(OfficialAnkiCsp.VALUE.contains("frame-src https://anki.local"))
        assertFalse(OfficialAnkiCsp.VALUE.contains("frame-src *"))
        assertTrue(OfficialAnkiCsp.VALUE.contains("form-action 'none'"))
        assertTrue(OfficialAnkiCsp.isShellUrl(OfficialAnkiCsp.SHELL_URL))
        assertFalse(OfficialAnkiCsp.isShellUrl("https://evil.example/"))
    }

    @Test
    fun assetAllowlistRejectsTraversal() {
        assertTrue(OfficialAnkiMediaPath.isSafeAssetName("reviewer.html"))
        assertTrue(OfficialAnkiMediaPath.isSafeAssetName("mathjax/tex-svg-full.js"))
        assertTrue(OfficialAnkiMediaPath.isSafeAssetName("card-frame.html"))
        assertFalse(OfficialAnkiMediaPath.isSafeAssetName("../secret.js"))
        assertFalse(OfficialAnkiMediaPath.isSafeAssetName("/etc/passwd"))
    }
}
