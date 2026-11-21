package co.visionairy.googly.proto

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.Base64
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executor
import java.util.concurrent.TimeUnit

/** Vectors were produced independently with Python `cryptography` (HKDF, AESGCM) and hashlib/hmac. */
class ProtocolTest {
    private val secret = ByteArray(32) { 17 }
    private val challenge = ByteArray(32) { it.toByte() }
    private fun hex(b: ByteArray) = b.joinToString("") { "%02x".format(it) }
    private val direct = Executor { it.run() }

    @Test fun hkdfMatchesRfc5869Case1() {
        val ikm = ByteArray(22) { 0x0b }
        val salt = ByteArray(13) { it.toByte() }
        val info = ByteArray(10) { (0xf0 + it).toByte() }
        assertEquals(
            "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865",
            hex(Crypto.hkdf(ikm, salt, info, 42)))
    }

    @Test fun directionKeysMatchIndependentVector() {
        assertEquals("ccfe489505023244ff17fcfc3cd8f74bb38d98b031e5fb0c39f8760c96b9ab2e",
            hex(Crypto.hkdf(secret, challenge, "bluey-v1-mac-to-phone".toByteArray(), 32)))
        assertEquals("88e25a45500c381185a50554fde6aca29120003b0630f212622aacf097439b05",
            hex(Crypto.hkdf(secret, challenge, "bluey-v1-phone-to-mac".toByteArray(), 32)))
    }

    @Test fun proofMatchesAndVerifies() {
        val proof = SecureChannel.proof(secret, challenge)
        assertEquals("A5pzRo8ci6dkYIBJyff+7PGWIxFVMriqV5ZUC7IVydc=", Base64.getEncoder().encodeToString(proof))
        assertTrue(SecureChannel.verifies(proof, secret, challenge))
        assertFalse(SecureChannel.verifies(proof, ByteArray(32) { 18 }, challenge))
        assertFalse(SecureChannel.verifies(proof.copyOf(31), secret, challenge))
    }

    @Test fun phoneOpensCombinedRecordSealedElsewhere() {
        // nonce(12) ‖ ciphertext ‖ tag(16), as CryptoKit's `combined`.
        val line = "BwcHBwcHBwcHBwcH+MwwoIczKG+gXWxSbcJr9nMB5mwcT5+bzic06n6BDNCYBAmVlIKFqQP88c8EI3xN8Dndyg9GFYZRCcQr"
        val phone = SecureChannel(secret, challenge, server = false)
        assertEquals("paired", phone.open(line.toByteArray()).command)
    }

    @Test fun sequenceMustMatchExactlyAndTamperingFails() {
        val mac = SecureChannel(secret, challenge, server = true)
        val phone = SecureChannel(secret, challenge, server = false)
        val first = mac.seal(Packet(command = "paired"))
        val second = mac.seal(Packet(command = "focusState", text = "{}"))
        // Wrong direction key: the phone can't open its own outgoing direction.
        assertThrows(ChannelException::class.java) { SecureChannel(secret, challenge, server = true).open(first) }
        // Out of order (replay/skip) closes.
        val skipped = SecureChannel(secret, challenge, server = false)
        assertThrows(ChannelException::class.java) { skipped.open(second) }
        assertEquals("paired", phone.open(first).command)
        assertThrows(ChannelException::class.java) { phone.open(first) } // replay
        val bad = Base64.getDecoder().decode(second).also { it[20] = (it[20].toInt() xor 1).toByte() }
        assertThrows(ChannelException::class.java) { phone.open(Base64.getEncoder().encode(bad)) }
        assertEquals("focusState", phone.open(second).command)
        // Each record carries a fresh nonce.
        assertNotEquals(String(mac.seal(Packet(command = "x"))).substring(0, 16), String(first).substring(0, 16))
    }

    @Test fun pairingRecordParsesLikeSwift() {
        val key = Base64.getEncoder().encodeToString(secret)
        val record = PairingRecord.parse(PairingRecord("Studio Mac", key).qrText)!!
        assertEquals("Studio Mac", record.service)
        assertEquals("02d449a31fbb267c8f352e99", record.identifier)
        fun qr(json: String) = "bluey-pair:" + Base64.getEncoder().encodeToString(json.toByteArray())
        assertNotNull(PairingRecord.parse(qr("""{"version":1,"service":"m","secret":"$key","extra":true}""")))
        assertNull(PairingRecord.parse(qr("""{"version":2,"service":"m","secret":"$key"}""")))
        assertNull(PairingRecord.parse(qr("""{"service":"m","secret":"$key"}""")))
        assertNull(PairingRecord.parse(qr("""{"version":1,"service":"","secret":"$key"}""")))
        assertNull(PairingRecord.parse(qr("""{"version":1,"service":"m","secret":"${Base64.getEncoder().encodeToString(ByteArray(31))}"}""")))
        assertNull(PairingRecord.parse("bluey-pair:%%%"))
        assertNull(PairingRecord.parse("other:" + record.qrText.substring(11)))
        assertNull(PairingRecord.parse("bluey-pair:" + "A".repeat(2040)))
        assertFalse(record.toString().contains(key))
    }

    @Test fun packetOmitsNilFieldsAndRejectsWrongTypes() {
        val json = Packet(command = "tool", callID = "1", tool = "look_at_screen", text = "{}").toJson()
        assertEquals(setOf("command", "callID", "tool", "text"), json.keys().asSequence().toSet())
        val face = Packet.fromJson(JSONObject("""{"face":{"gazeX":0.5,"gazeY":-1,"mood":"pointing","talk":0}}""")).face!!
        assertEquals(Mood.pointing, face.mood); assertEquals(-1.0, face.gazeY, 0.0)
        assertThrows(IllegalArgumentException::class.java) { Packet.fromJson(JSONObject("""{"face":{"gazeX":0,"gazeY":0,"mood":"angry","talk":0}}""")) }
        assertThrows(Exception::class.java) { Packet.fromJson(JSONObject("""{"command":3}""")) }
        assertEquals(7, Packet.fromJson(JSONObject("""{"speech":7,"command":"stopSpeech"}""")).speech)
    }

    @Test fun loopbackHandshakeDeliversEncryptedPacketsBothWays() {
        val server = ServerSocket(0, 1, InetAddress.getLoopbackAddress())
        val authenticated = CountDownLatch(2)
        val delivered = CountDownLatch(2)
        var mac: LineConnection? = null
        Thread {
            mac = LineConnection(server.accept(), secret, server = true, callbacks = direct).apply {
                onAuthenticated = { authenticated.countDown(); send(Packet(hello = "Mac")) }
                onPacket = { if (it.command == "focusStart" && it.text == "A private focus task") delivered.countDown() }
                start()
            }
        }.start()
        val phone = LineConnection(Socket(server.inetAddress, server.localPort), secret, server = false, callbacks = direct).apply {
            onAuthenticated = { authenticated.countDown(); send(Packet(command = "focusStart", text = "A private focus task")) }
            onPacket = { if (it.hello == "Mac") delivered.countDown() }
            start()
        }
        assertTrue(authenticated.await(8, TimeUnit.SECONDS))
        assertTrue(delivered.await(8, TimeUnit.SECONDS))
        phone.cancel(); mac?.cancel(); server.close()
    }

    @Test fun wrongSecretIsRejected() {
        val server = ServerSocket(0, 1, InetAddress.getLoopbackAddress())
        val closed = CountDownLatch(1)
        var macAuth = false
        Thread {
            LineConnection(server.accept(), secret, server = true, callbacks = direct).apply {
                onAuthenticated = { macAuth = true }; start()
            }
        }.start()
        val phone = LineConnection(Socket(server.inetAddress, server.localPort), ByteArray(32) { 1 }, server = false, callbacks = direct).apply {
            onClosed = { closed.countDown() }; start()
        }
        assertTrue(closed.await(9, TimeUnit.SECONDS))
        assertFalse(phone.authenticated); assertFalse(macAuth)
        server.close()
    }
}
