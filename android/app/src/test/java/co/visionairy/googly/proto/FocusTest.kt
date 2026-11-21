package co.visionairy.googly.proto

import org.junit.Assert.*
import org.junit.Test

/** Ports of Tests/GooglySharedTests/FocusTests.swift plus decoding of Mac payloads. */
class FocusTest {
    private fun off(t: Double, p: Double = 0.99) = FocusCheck("x", t, FocusActivity.offTask, p, p)

    @Test fun developerObservationsUseAcceleratedNudgeTime() {
        val policy = FocusNudgePolicy(60.0, developerMode = true)
        assertFalse(policy.observe(off(40.0), 1.0))
        assertTrue(policy.observe(off(80.0), 1.0))
        assertFalse(policy.observe(off(120.0), 1.0))
        assertFalse(policy.observe(off(160.0), 1.0))
        assertTrue(policy.observe(off(200.0), 1.0))
        assertFalse(policy.observe(off(240.0), 21.0))
        val gap = FocusNudgePolicy(60.0, developerMode = true)
        assertFalse(gap.observe(off(40.0), 1.0)); assertFalse(gap.observe(off(120.0), 1.0))
    }

    @Test fun confidenceIsNotASecondVeto() {
        val normal = FocusNudgePolicy()
        for (t in 0..180 step 30) assertFalse(normal.observe(FocusCheck("x", t.toDouble(), FocusActivity.offTask, 0.7, 0.1), 1.0))
        assertTrue(normal.observe(FocusCheck("x", 210.0, FocusActivity.offTask, 0.7, 0.1), 1.0))
    }

    @Test fun twoMinuteMinimumModerateEvidenceAndResets() {
        val policy = FocusNudgePolicy()
        for (t in 30..120 step 30) assertFalse(policy.observe(off(t.toDouble()), 1.0))
        assertTrue(policy.observe(off(150.0), 1.0))
        val moderate = FocusNudgePolicy()
        for (t in 0..180 step 30) assertFalse(moderate.observe(off(t.toDouble(), 0.65), 2.0))
        assertTrue(moderate.observe(off(210.0, 0.65), 2.0))
        for (a in listOf(FocusActivity.onTask, FocusActivity.uncertain, FocusActivity.unavailable, FocusActivity.paused)) {
            val p = FocusNudgePolicy()
            for (t in listOf(0.0, 30.0, 60.0, 90.0)) assertFalse(p.observe(off(t), 1.0))
            assertFalse(p.observe(FocusCheck("x", 120.0, a), 1.0))
            for (t in listOf(150.0, 180.0, 210.0, 240.0)) assertFalse(p.observe(off(t), 1.0))
            assertTrue(p.observe(off(270.0), 1.0))
        }
        val stale = FocusNudgePolicy()
        assertFalse(stale.observe(off(0.0), -1.0)); assertFalse(stale.observe(off(Double.NaN), 1.0))
    }

    @Test fun decisionDecodeAcceptsContractAndRejectsMalformed() {
        val ok = """{"answers":[{"name":"activity","type":"choice","choice":"off_task","confidence":0.8,
            "probabilities":[{"value":"on_task","probability":0.1},{"value":"off_task","probability":0.85},{"value":"uncertain","probability":0.05}]}]}"""
        val d = FocusDecision.decode(ok)
        assertEquals(FocusActivity.offTask, d.activity); assertEquals(0.85, d.probability, 0.0); assertEquals(0.8, d.confidence, 0.0)
        val bad = listOf(
            ok.replace("off_task\",\"confidence", "paused\",\"confidence"),
            ok.replace("0.85", "0.5"), // sum off by more than 0.02
            ok.replace("\"on_task\",\"probability\"", "\"off_task\",\"probability\""), // duplicate
            ok.replace("0.8,", "1.5,"),
            ok.replace("\"choice\",\"choice\"", "\"text\",\"choice\""),
            """{"answers":[]}""", "not json",
        )
        for (b in bad) assertThrows(b, IllegalArgumentException::class.java) { FocusDecision.decode(b) }
    }

    @Test fun focusSyncDecodesSwiftEncodedPayload() {
        // Shape of Swift JSONEncoder output: UUID strings, Date as reference-date seconds, optional keys omitted.
        val text = """{"current":{"id":"2D5E2C4A-0B7B-4A54-9C27-7A1A9C8F0E11","task":"Write docs","duration":1800,
            "startedAt":785000000.5,"elapsed":64,"status":"running","detail":"Next check in 30 seconds",
            "checks":[{"id":"A0B1","elapsed":30,"activity":"on_task","probability":0.1,"confidence":0.9,
            "probabilities":{"on_task":0.85,"off_task":0.1,"uncertain":0.05},"sampleDuration":30,"nudged":false},
            {"id":"A0B2","elapsed":60,"activity":"paused","probability":0,"confidence":0,"nudged":false}]},
            "history":[],"revision":4,"sentAt":785000064.25}"""
        val sync = FocusSync.decode(text)!!
        val s = sync.current!!
        assertEquals(4, sync.revision); assertNull(sync.developerMode)
        assertEquals(FocusStatus.running, s.status); assertEquals(1.0, s.clockRate, 0.0)
        assertEquals(64.0, s.realActiveElapsed, 0.0); assertEquals(1736.0, s.remaining, 0.0)
        assertEquals(0.85, s.checks[0].estimate(FocusActivity.onTask)!!, 0.0)
        assertNull(s.checks[1].estimate(FocusActivity.offTask))
        assertEquals("29:00", FocusSession.clock(1739.2)) // rounds up like Swift
        assertNull(FocusSync.decode(text.replace(",\"sentAt\":785000064.25", "")))
    }
}
