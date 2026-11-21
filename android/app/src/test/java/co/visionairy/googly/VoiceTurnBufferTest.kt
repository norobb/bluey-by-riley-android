package co.visionairy.googly

import org.junit.Assert.*
import org.junit.Test

/** Port of testVoiceRetainsBeginningUntilConnectedAndRejectsEmptyTurns, at 16 kHz (100 ms = 3200 bytes). */
class VoiceTurnBufferTest {
    @Test fun retainsBeginningUntilConnectedAndRejectsShortTurns() {
        val turn = VoiceTurnBuffer()
        assertFalse(turn.canCommit)
        val beginning = ByteArray(3200) { 1 }
        assertNull(turn.append(beginning, ready = false))
        assertTrue(turn.canCommit)
        assertArrayEquals(beginning, turn.connected().single())
        assertTrue(turn.connected().isEmpty())
        val next = ByteArray(3200) { 2 }
        assertSame(next, turn.append(next, ready = true))
        turn.begin(); assertFalse(turn.canCommit)
        assertNull(turn.append(ByteArray(640_001), ready = false))
        assertTrue(turn.overflowed); assertFalse(turn.canCommit)
    }
}
