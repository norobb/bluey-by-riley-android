package co.visionairy.googly.proto

import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.OutputStream
import java.net.Socket
import java.util.Base64
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Newline-delimited records over one TCP socket, with the challenge/proof handshake from
 * Shared/GooglyLink.swift. Server = Mac, client = phone. Callbacks run on [callbacks].
 */
class LineConnection(
    private val socket: Socket,
    private val secret: ByteArray,
    private val server: Boolean,
    private val callbacks: Executor,
) {
    var onPacket: ((Packet) -> Unit)? = null
    var onAuthenticated: (() -> Unit)? = null
    var onClosed: (() -> Unit)? = null

    /** Why the link closed, for diagnostics; never contains key material. */
    @Volatile var closeReason = "closed"; private set
    @Volatile private var channel: SecureChannel? = null
    @Volatile var authenticated = false; private set
    private var challenge: ByteArray? = null
    private val closed = AtomicBoolean(false)
    private val writer = Executors.newSingleThreadExecutor()
    private lateinit var out: OutputStream

    fun start() {
        Thread({
            try {
                socket.tcpNoDelay = true
                socket.keepAlive = true
                out = socket.getOutputStream()
                if (server) {
                    val c = Crypto.randomBytes(32)
                    challenge = c
                    handshake("challenge", Base64.getEncoder().encodeToString(c))
                }
                readLoop()
            } catch (e: Exception) {
                closeReason = e.toString()
            } finally { cancel() }
        }, "bluey-link").start()
        timer.schedule({ if (!authenticated) cancel() }, AUTH_TIMEOUT_S, TimeUnit.SECONDS)
    }

    fun send(packet: Packet) {
        val channel = channel ?: return
        if (!authenticated || closed.get()) return
        // Sealing happens on the writer thread so sequence order equals wire order.
        runCatching { writer.execute { runCatching { write(channel.seal(packet)) }.onFailure { cancel() } } }
    }

    fun cancel() {
        if (!closed.compareAndSet(false, true)) return
        // Close after queued writes, so a last request (e.g. focusPause on backgrounding) still goes out.
        runCatching { writer.execute { runCatching { socket.close() } } }.onFailure { runCatching { socket.close() } }
        writer.shutdown()
        callbacks.execute { onClosed?.invoke() }
    }

    val isClosed get() = closed.get()

    private fun write(data: ByteArray) {
        synchronized(this) { out.write(data + NEWLINE); out.flush() }
    }

    private fun handshake(key: String, value: String) {
        val line = JSONObject().put(key, value).toString().toByteArray()
        runCatching { writer.execute { runCatching { write(line) }.onFailure { cancel() } } }
    }

    private fun readLoop() {
        val input = socket.getInputStream()
        val buffer = ByteArrayOutputStream()
        val chunk = ByteArray(64 * 1024)
        while (!closed.get()) {
            val n = input.read(chunk)
            if (n < 0) return
            var start = 0
            for (i in 0 until n) {
                if (chunk[i] == NEWLINE_BYTE) {
                    buffer.write(chunk, start, i - start)
                    val line = buffer.toByteArray()
                    buffer.reset()
                    start = i + 1
                    if (!accept(line)) { closeReason = "rejected record (handshake or channel)"; return }
                }
            }
            buffer.write(chunk, start, n - start)
            if (buffer.size() > MAX_BUFFER) return
        }
    }

    /** Returns false when the connection must close. */
    private fun accept(line: ByteArray): Boolean {
        channel?.let { ch ->
            val packet = try { ch.open(line) } catch (_: Exception) { return false }
            if (!authenticated) {
                if (server || packet.command != "paired") return false
                authenticated = true
                callbacks.execute { if (!closed.get()) onAuthenticated?.invoke() }
            } else callbacks.execute { if (!closed.get()) onPacket?.invoke(packet) }
            return true
        }
        val json = runCatching { JSONObject(String(line, Charsets.UTF_8)) }.getOrNull() ?: return false
        // Swift casts to [String: String]: every value must be a string.
        if (json.keys().asSequence().any { json.opt(it) !is String }) return false
        if (server) {
            val c = challenge ?: return false
            val text = json.opt("proof") as? String ?: return false
            val proof = runCatching { Base64.getDecoder().decode(text) }.getOrNull() ?: return false
            if (!SecureChannel.verifies(proof, secret, c)) return false
            channel = SecureChannel(secret, c, server = true)
            authenticated = true
            send(Packet(command = "paired"))
            callbacks.execute { onAuthenticated?.invoke() }
        } else {
            if (!json.has("challenge")) return false
            val c = runCatching { Base64.getDecoder().decode(json.getString("challenge")) }.getOrNull() ?: return false
            if (c.size != 32) return false
            channel = SecureChannel(secret, c, server = false)
            handshake("proof", Base64.getEncoder().encodeToString(SecureChannel.proof(secret, c)))
        }
        return true
    }

    companion object {
        const val AUTH_TIMEOUT_S = 8L
        const val MAX_BUFFER = 16 * 1024 * 1024
        private const val NEWLINE_BYTE: Byte = 0x0A
        private val NEWLINE = byteArrayOf(NEWLINE_BYTE)
        private val timer = Executors.newSingleThreadScheduledExecutor { Thread(it, "bluey-auth-timer").apply { isDaemon = true } }
    }
}
