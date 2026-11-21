package co.visionairy.googly.proto

import org.json.JSONObject
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/** Mirrors Shared/GooglyLink.swift and Shared/SecurePairing.swift byte for byte. */
object GooglyService {
    const val TYPE = "_googly._tcp"
}

enum class Mood { listening, resting, thinking, talking, pointing, happy, sleepy;
    companion object { fun of(raw: String?) = entries.firstOrNull { it.name == raw } }
}

data class FaceState(val gazeX: Double = 0.0, val gazeY: Double = 0.0, val mood: Mood = Mood.listening, val talk: Double = 0.0) {
    fun toJson(): JSONObject = JSONObject().put("gazeX", gazeX).put("gazeY", gazeY).put("mood", mood.name).put("talk", talk)
    companion object {
        /** Swift's synthesized decoder requires all four keys and a known mood. */
        fun fromJson(o: JSONObject): FaceState? {
            val mood = Mood.of(o.optString("mood", "")) ?: return null
            if (!o.has("gazeX") || !o.has("gazeY") || !o.has("talk")) return null
            return FaceState(o.getDouble("gazeX"), o.getDouble("gazeY"), mood, o.getDouble("talk"))
        }
    }
}

/** Every field optional; nil fields are omitted, like Swift's JSONEncoder. */
data class Packet(
    val face: FaceState? = null,
    val hello: String? = null,
    val volume: Double? = null,
    val command: String? = null,
    val audio: String? = null,
    val speech: Int? = null,
    val callID: String? = null,
    val tool: String? = null,
    val text: String? = null,
    val image: String? = null,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        face?.let { put("face", it.toJson()) }
        hello?.let { put("hello", it) }
        volume?.let { put("volume", it) }
        command?.let { put("command", it) }
        audio?.let { put("audio", it) }
        speech?.let { put("speech", it) }
        callID?.let { put("callID", it) }
        tool?.let { put("tool", it) }
        text?.let { put("text", it) }
        image?.let { put("image", it) }
    }

    companion object {
        fun fromJson(o: JSONObject): Packet {
            fun str(k: String) = if (o.isNull(k)) null else o.get(k).let { it as? String ?: throw IllegalArgumentException(k) }
            val face = if (o.isNull("face")) null else FaceState.fromJson(o.getJSONObject("face")) ?: throw IllegalArgumentException("face")
            return Packet(
                face = face,
                hello = str("hello"),
                volume = if (o.isNull("volume")) null else o.getDouble("volume"),
                command = str("command"),
                audio = str("audio"),
                speech = if (o.isNull("speech")) null else o.getInt("speech"),
                callID = str("callID"),
                tool = str("tool"),
                text = str("text"),
                image = str("image"),
            )
        }
    }
}

/** The QR pairing credential. Never log [secret]. */
class PairingRecord(val service: String, val secret: String, val version: Int = 1) {
    val key: ByteArray? get() = runCatching { Base64.getDecoder().decode(secret) }.getOrNull()?.takeIf { it.size == 32 }

    /** First 12 bytes of SHA-256(key), lowercase hex: the Bonjour TXT `bluey-id`. */
    val identifier: String get() = key?.let { k ->
        MessageDigest.getInstance("SHA-256").digest(k).take(12).joinToString("") { "%02x".format(it) }
    } ?: "invalid"

    fun toJson(): JSONObject = JSONObject().put("version", version).put("service", service).put("secret", secret)
    val qrText: String get() = "bluey-pair:" + Base64.getEncoder().encodeToString(toJson().toString().toByteArray())

    override fun toString() = "PairingRecord(service=$service)" // keeps the secret out of logs

    companion object {
        fun parse(text: String): PairingRecord? {
            // Swift's String.count counts grapheme clusters; the payload is ASCII so length matches.
            if (!text.startsWith("bluey-pair:") || text.length >= 2048) return null
            return runCatching {
                val json = JSONObject(String(Base64.getDecoder().decode(text.substring(11)), Charsets.UTF_8))
                fromJson(json)
            }.getOrNull()
        }

        fun fromJson(json: JSONObject): PairingRecord? {
            // Swift decodes `version` with a default only when the key is present; missing keys fail.
            val version = json.opt("version") as? Int ?: return null
            val service = json.opt("service") as? String ?: return null
            val secret = json.opt("secret") as? String ?: return null
            val record = PairingRecord(service, secret, version)
            return if (version == 1 && record.key != null && service.isNotEmpty()) record else null
        }
    }
}

object Crypto {
    private val random = SecureRandom()
    fun randomBytes(n: Int) = ByteArray(n).also { random.nextBytes(it) }

    fun hmac(key: ByteArray, data: ByteArray): ByteArray =
        Mac.getInstance("HmacSHA256").run { init(SecretKeySpec(key, "HmacSHA256")); doFinal(data) }

    /** RFC 5869 HKDF-SHA256, the same as CryptoKit's HKDF<SHA256>.deriveKey. */
    fun hkdf(ikm: ByteArray, salt: ByteArray, info: ByteArray, length: Int): ByteArray {
        val prk = hmac(if (salt.isEmpty()) ByteArray(32) else salt, ikm)
        val out = java.io.ByteArrayOutputStream()
        var t = ByteArray(0)
        var i = 1
        while (out.size() < length) {
            t = hmac(prk, t + info + byteArrayOf(i.toByte()))
            out.write(t); i++
        }
        return out.toByteArray().copyOf(length)
    }

    /** CryptoKit `AES.GCM.SealedBox.combined`: 12-byte nonce + ciphertext + 16-byte tag. */
    fun sealCombined(key: ByteArray, plain: ByteArray): ByteArray {
        val nonce = randomBytes(12)
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce))
        return nonce + c.doFinal(plain)
    }

    fun openCombined(key: ByteArray, combined: ByteArray): ByteArray {
        require(combined.size >= 28)
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, combined, 0, 12))
        return c.doFinal(combined, 12, combined.size - 12)
    }
}

class ChannelException : Exception("invalid record")

/** Challenge-derived direction keys and ordered AES-GCM records (Shared/SecurePairing.swift). */
class SecureChannel(secret: ByteArray, challenge: ByteArray, server: Boolean) {
    private val sendKey: ByteArray
    private val receiveKey: ByteArray
    private var sent = 0
    private var received = 0

    init {
        fun key(direction: String) = Crypto.hkdf(secret, challenge, "bluey-v1-$direction".toByteArray(), 32)
        sendKey = key(if (server) "mac-to-phone" else "phone-to-mac")
        receiveKey = key(if (server) "phone-to-mac" else "mac-to-phone")
    }

    @Synchronized
    fun seal(packet: Packet): ByteArray {
        val record = JSONObject().put("sequence", sent).put("packet", packet.toJson())
        val encrypted = Crypto.sealCombined(sendKey, record.toString().toByteArray(Charsets.UTF_8))
        sent += 1
        return Base64.getEncoder().encode(encrypted)
    }

    @Synchronized
    fun open(line: ByteArray): Packet {
        try {
            val encrypted = Base64.getDecoder().decode(line)
            val record = JSONObject(String(Crypto.openCombined(receiveKey, encrypted), Charsets.UTF_8))
            val sequence = record.get("sequence") as? Int ?: throw ChannelException()
            val packet = Packet.fromJson(record.getJSONObject("packet"))
            if (sequence != received) throw ChannelException()
            received += 1
            return packet
        } catch (e: ChannelException) { throw e } catch (e: Exception) { throw ChannelException() }
    }

    companion object {
        private val LABEL = "bluey-pair-v1".toByteArray()
        fun proof(secret: ByteArray, challenge: ByteArray) = Crypto.hmac(secret, LABEL + challenge)
        fun verifies(proof: ByteArray, secret: ByteArray, challenge: ByteArray) =
            MessageDigest.isEqual(proof, proof(secret, challenge)) // constant time
    }
}
