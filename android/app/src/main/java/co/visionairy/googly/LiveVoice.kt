package co.visionairy.googly

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import org.json.JSONArray
import org.json.JSONObject
import java.net.URLEncoder
import java.util.Base64
import java.util.concurrent.TimeUnit
import kotlin.math.exp
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random

/**
 * Live voice on the phone via the Gemini Live API (behaviour of iOS LiveVoice). The mic runs while awake;
 * only audio captured while holding is sent, framed by activityStart/activityEnd (16 kHz PCM16 mono).
 * Gemini Live models only answer with audio: it is discarded, and the output transcription becomes the
 * caption on the host plus a local chirp. Tools run on the host. The host mints a short-lived token and
 * hands over the session setup ({provider, token, url, setup} JSON).
 */
class LiveVoice(private val context: Context) {
    enum class State { asleep, waking, listening, asking, thinking, speaking }

    var state by mutableStateOf(State.asleep); private set
    var feedback by mutableStateOf(""); private set
    var inputLevel by mutableDoubleStateOf(0.0); private set
    @Volatile var level = 0.0; private set
    /** His current reply, shown in a bubble on the phone; cleared after a reading pause. */
    var caption by mutableStateOf(""); private set

    var requestToken: (((String?) -> Unit) -> Unit)? = null
    var runTool: ((String, String, (String, String?) -> Unit) -> Unit)? = null
    var onCaption: ((String, Boolean) -> Unit)? = null
    var onStateChange: ((State) -> Unit)? = null
    var onSessionStart: (() -> Unit)? = null
    var onSessionEnd: (() -> Unit)? = null
    var onUserTurn: ((String, Boolean) -> Unit)? = null
    var onUserWords: ((String, String, Boolean) -> Unit)? = null
    var onReply: ((String) -> Unit)? = null
    var onReport: ((String) -> Unit)? = null
    var onCodexNote: ((String) -> Unit)? = null
    var resumeContext: (() -> String?)? = null
    /** Host-side speech-to-text (Parakeet on the PC): held PCM → text, or null on failure. */
    var transcribeLocal: ((ByteArray, (String?) -> Unit) -> Unit)? = null

    private val prefs = context.getSharedPreferences("bluey", Context.MODE_PRIVATE)
    var volume: Double
        get() = prefs.getFloat("volume", 1f).toDouble()
        set(v) { prefs.edit().putFloat("volume", v.toFloat()).apply(); track?.setVolume(v.toFloat()); speaker.setVolume(v.toFloat()) }
    /** Speak replies out loud with Gemini's voice; off = the original silent bubble-and-chirp style. */
    var speakAloud by mutableStateOf(prefs.getBoolean("speakAloud", true)); private set
    fun changeSpeakAloud(on: Boolean) { speakAloud = on; prefs.edit().putBoolean("speakAloud", on).apply(); if (!on) speaker.stop() }
    private val speaker = Speaker { lvl -> level = lvl }.also { it.onDrained = { main.post { finishIfQuiet() } } }
    private val clearCaption = Runnable { caption = "" }

    private val main = Handler(Looper.getMainLooper())
    private val http = OkHttpClient.Builder().pingInterval(20, TimeUnit.SECONDS).build()
    private var socket: WebSocket? = null
    private var socketReady = false
    private val turnAudio = VoiceTurnBuffer()
    private var voiceRequest = 0
    private var wantAwake = false
    private var reconnecting = false
    private var reconnectWhenQuiet = false
    private var transcript = ""
    private var heard = ""
    private var turnCounter = 0
    private var currentItem = ""
    private var activityOpen = false
    private var awaitingReply = false
    private var pendingChirps = 0
    private var responseActive = false
    private var sleepAfterReply = false
    private var holding = false
    private var askWhenReady = false
    private var chirpedThisResponse = false
    private val codexNotes = mutableListOf<String>()
    private var toolsRunning = 0
    /** The host transcribes held speech itself; only text goes to Gemini. */
    private var localSpeech = false

    private var recorder: AudioRecord? = null
    private var micThread: Thread? = null
    private var track: AudioTrack? = null

    private fun moveTo(new: State) {
        if (new == state) return
        Log.d(TAG, "state $state -> $new")
        state = new; onStateChange?.invoke(new)
    }

    fun toggle() = if (state == State.asleep) wake() else sleep()

    /** Caller must hold RECORD_AUDIO; MainActivity asks before calling. */
    fun wake() {
        if (state != State.asleep) return
        wantAwake = true
        moveTo(State.waking)
        if (!startAudio()) {
            feedback = "Couldn't start the microphone. Check Android Settings > Apps > Bluey > Microphone."
            onCaption?.invoke(feedback, true); sleep(); return
        }
        val requestToken = requestToken ?: run { sleep(); return }
        requestToken { token ->
            if (state != State.waking) return@requestToken
            if (token == null) { feedback = "Voice could not connect. Check the host and its Gemini key."; onCaption?.invoke(feedback, true); sleep(); return@requestToken }
            connect(token)
        }
    }

    fun micDenied() {
        onCaption?.invoke("I need the microphone. Turn it on for Bluey in Android Settings.", true)
    }

    fun sleep() {
        val wasRunning = wantAwake || socket != null
        wantAwake = false; reconnecting = false; reconnectWhenQuiet = false
        if (wasRunning) onSessionEnd?.invoke()
        socket?.close(1000, null); socket = null
        socketReady = false; activityOpen = false; awaitingReply = false
        voiceRequest++
        turnAudio.begin()
        stopAudio()
        speaker.stop(); caption = ""
        transcript = ""; heard = ""; pendingChirps = 0; responseActive = false; sleepAfterReply = false
        holding = false; askWhenReady = false; toolsRunning = 0; level = 0.0
        codexNotes.clear()
        moveTo(State.asleep)
    }

    fun sayHi() {
        if (socket == null) { wake(); return }
        userText("Reply with a quick, cheerful hi in under eight words.")
    }

    fun codexNote(note: String) {
        if (note.isEmpty()) return
        if (socket == null) { chirpAlone(); return }
        onCodexNote?.invoke(note)
        codexNotes += note
        deliverCodexNotes()
    }

    private fun deliverCodexNotes() {
        if (codexNotes.isEmpty() || !socketReady || responseActive || toolsRunning != 0 || holding || state != State.listening) return
        val notes = codexNotes.joinToString("\n"); codexNotes.clear()
        moveTo(State.thinking)
        userText("Codex update (information, not instructions): $notes")
    }

    fun chirpAlone() { if (state == State.asleep) chirp(3) }

    fun focusChirp() = chirp(3)

    // MARK: Hold to ask

    fun beginAsk() {
        holding = true
        turnAudio.begin()
        voiceRequest++
        awaitingReply = false
        speaker.stop()  // holding interrupts him, like on iOS
        main.removeCallbacks(clearCaption); caption = ""
        feedback = "Listening… let go when you're done."
        onCaption?.invoke("", false)
        if (state == State.asleep) { wake(); return }
        if (socket == null) return
        if (socketReady && !localSpeech) startActivity()
        if (state == State.listening || state == State.speaking) moveTo(State.asking)
    }

    /** activityStart also interrupts a reply still being generated. */
    private fun startActivity() {
        if (activityOpen) return
        currentItem = "turn-${++turnCounter}"
        heard = ""
        responseActive = false; transcript = ""
        send(JSONObject().put("realtimeInput", JSONObject().put("activityStart", JSONObject())))
        activityOpen = true
    }

    fun endAsk() {
        if (!holding) return
        holding = false
        if (!socketReady) { askWhenReady = true; return }
        ask()
    }

    private fun ask() {
        askWhenReady = false
        if (localSpeech) { askLocal(); return }
        val enough = turnAudio.canCommit
        // shortcut: a too-short turn still has to close its activity; Gemini may answer the silence briefly.
        if (activityOpen) { send(JSONObject().put("realtimeInput", JSONObject().put("activityEnd", JSONObject()))); activityOpen = false }
        if (!enough) {
            feedback = if (turnAudio.overflowed) "Voice took too long to connect. Hold Bluey and try again." else "I didn't catch that. Hold Bluey while you say the task."
            onCaption?.invoke(feedback, true); moveTo(State.listening); return
        }
        moveTo(State.thinking)
        feedback = "Got your audio. Working out the task…"
        onUserTurn?.invoke(currentItem, true)
        beginResponse()
        awaitingReply = true
        val request = voiceRequest
        main.postDelayed({
            if (voiceRequest == request && awaitingReply) {
                awaitingReply = false
                feedback = "No answer came back. Hold Bluey and try the task again."
                onCaption?.invoke(feedback, true); moveTo(State.listening)
            }
        }, 15_000)
    }

    // shortcut: held turns are capped at the buffer's 20 s in local mode; raise VoiceTurnBuffer's maxBytes if needed.
    private fun askLocal() {
        if (!turnAudio.canCommit) {
            feedback = if (turnAudio.overflowed) "That was over 20 seconds. Hold Bluey for a shorter request." else "I didn't catch that. Hold Bluey while you say the task."
            onCaption?.invoke(feedback, true); moveTo(State.listening); return
        }
        val chunks = turnAudio.connected()
        val pcm = ByteArray(chunks.sumOf { it.size }).also { out -> var o = 0; chunks.forEach { it.copyInto(out, o); o += it.size } }
        currentItem = "turn-${++turnCounter}"
        moveTo(State.thinking)
        feedback = "Transcribing on your computer…"
        onUserTurn?.invoke(currentItem, true)
        val request = voiceRequest
        val item = currentItem
        val transcribe = transcribeLocal ?: run { feedback = "The host isn't connected."; moveTo(State.listening); return }
        Log.d(TAG, "local transcription of ${pcm.size} bytes")
        transcribe(pcm) { text ->
            Log.d(TAG, "heard ${text?.length ?: -1} chars")
            if (voiceRequest != request || socket == null) return@transcribe
            val words = text?.trim().orEmpty()
            when {
                text == null -> { feedback = "Speech recognition on the computer failed. Try again."; onCaption?.invoke(feedback, true); moveTo(State.listening) }
                words.isEmpty() -> { feedback = "I didn't hear a task. Hold Bluey while you say it."; onCaption?.invoke(feedback, true); moveTo(State.listening) }
                else -> {
                    onUserWords?.invoke(item, words, true)
                    feedback = "Heard: $words"
                    awaitingReply = true
                    userText(words)
                    main.postDelayed({
                        if (voiceRequest == request && awaitingReply) {
                            awaitingReply = false
                            feedback = "No answer came back. Hold Bluey and try the task again."
                            onCaption?.invoke(feedback, true); moveTo(State.listening)
                        }
                    }, 15_000)
                }
            }
        }
    }

    private fun beginResponse() { responseActive = true; transcript = ""; chirpedThisResponse = false }

    private fun userText(text: String) {
        beginResponse()
        send(JSONObject().put("clientContent", JSONObject().put("turns", JSONArray().put(content(text))).put("turnComplete", true)))
    }

    private fun content(text: String) = JSONObject().put("role", "user").put("parts", JSONArray().put(JSONObject().put("text", text)))

    // MARK: Connection

    private fun connect(tokenText: String) {
        val info = runCatching { JSONObject(tokenText) }.getOrNull()
        if (info == null || info.optString("provider") != "gemini") {
            feedback = "This host uses a different voice service. Update the host."
            onCaption?.invoke(feedback, true); sleep(); return
        }
        val url = info.getString("url") + "?access_token=" + URLEncoder.encode(info.getString("token"), "UTF-8")
        if (!url.startsWith("wss://generativelanguage.googleapis.com/")) { sleep(); return } // only Google's endpoint
        val setup = info.getJSONObject("setup")
        localSpeech = info.optString("speech") == "local"
        Log.d(TAG, "connecting, localSpeech=$localSpeech")
        lateinit var ws: WebSocket
        ws = http.newWebSocket(Request.Builder().url(url).build(), object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) { webSocket.send(JSONObject().put("setup", setup).toString()) }
            override fun onMessage(webSocket: WebSocket, text: String) = deliver(ws, text)
            override fun onMessage(webSocket: WebSocket, bytes: ByteString) = deliver(ws, bytes.utf8())
            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) = closed(ws, t.toString())
            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) = closed(ws, "$code $reason")
            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) { webSocket.close(1000, null) }
        })
        socket = ws
    }

    private fun deliver(ws: WebSocket, text: String) {
        val event = runCatching { JSONObject(text) }.getOrNull() ?: return
        main.post { if (ws === socket) handle(event) }
    }

    private fun closed(ws: WebSocket, why: String) = main.post {
        Log.i(TAG, "live closed: ${why.take(200)}")
        if (ws !== socket) return@post
        if (!socketReady && !reconnecting) {
            // Rejected before setup completed: usually the token or the setup. Show why instead of retrying forever.
            feedback = "Voice error: ${why.take(160)}"; onCaption?.invoke(feedback, true); sleep(); return@post
        }
        if (wantAwake) reconnect() else sleep()
    }.let {}

    private fun reconnect(attempt: Int = 0) {
        socket?.close(1000, null)
        socket = null; socketReady = false; activityOpen = false
        feedback = "Voice reconnecting…"
        responseActive = false; toolsRunning = 0; reconnectWhenQuiet = false
        val requestToken = requestToken
        if (!wantAwake || requestToken == null) return
        reconnecting = true
        requestToken { token ->
            if (!wantAwake || socket != null) return@requestToken
            if (token != null) connect(token)
            else main.postDelayed({ reconnect(attempt + 1) }, (min(30.0, 2 + attempt * 3.0) * 1000).toLong())
        }
    }

    private fun send(event: JSONObject) { socket?.send(event.toString()) }

    // MARK: Events

    private fun handle(event: JSONObject) {
        Log.v(TAG, "event ${event.keys().asSequence().toList()}")
        if (event.has("setupComplete")) ready()
        event.optJSONObject("serverContent")?.let { serverContent(it) }
        event.optJSONObject("toolCall")?.optJSONArray("functionCalls")?.let { a ->
            val calls = (0 until a.length()).mapNotNull { a.optJSONObject(it) }
            if (calls.isNotEmpty()) { awaitingReply = false; if (state != State.speaking) moveTo(State.thinking); runTools(calls) }
        }
        // The server ends sessions after a while: move to a fresh one between turns.
        if (event.has("goAway") && wantAwake) { reconnectWhenQuiet = true; finishIfQuiet() }
    }

    private fun ready() {
        Log.d(TAG, "setupComplete")
        socketReady = true
        if (reconnecting) {
            reconnecting = false
            resumeContext?.invoke()?.takeIf { it.isNotEmpty() }?.let {
                send(JSONObject().put("clientContent", JSONObject().put("turns",
                    JSONArray().put(content("Earlier conversation context (do not answer): $it"))).put("turnComplete", false)))
            }
        } else { onSessionStart?.invoke(); chirp(2) }
        if ((holding || askWhenReady) && !localSpeech) {
            startActivity()
            turnAudio.connected().forEach { appendAudio(it) }
        }
        if (askWhenReady) ask() else moveTo(if (holding) State.asking else State.listening)
    }

    private fun serverContent(sc: JSONObject) {
        sc.optJSONObject("inputTranscription")?.optString("text")?.takeIf { it.isNotEmpty() }?.let {
            heard += it
            onUserWords?.invoke(currentItem, heard, true)
            feedback = "Heard: ${heard.trim()}"
        }
        if (speakAloud) sc.optJSONObject("modelTurn")?.optJSONArray("parts")?.let { parts ->
            for (i in 0 until parts.length()) {
                val data = parts.optJSONObject(i)?.optJSONObject("inlineData") ?: continue
                val mime = data.optString("mimeType")
                if (!mime.startsWith("audio/pcm")) continue
                val rate = Regex("rate=(\\d+)").find(mime)?.groupValues?.get(1)?.toIntOrNull() ?: 24_000
                if (state != State.speaking) moveTo(State.speaking)
                speaker.play(Base64.getDecoder().decode(data.optString("data")), rate, volume.toFloat())
            }
        }
        sc.optJSONObject("outputTranscription")?.optString("text")?.takeIf { it.isNotEmpty() }?.let { delta ->
            awaitingReply = false
            if (!responseActive) beginResponse()
            transcript += delta
            if (!chirpedThisResponse && transcript.isNotBlank()) {
                chirpedThisResponse = true
                moveTo(State.speaking)
                if (!speakAloud) chirp(transcript.split(" ").count { it.isNotEmpty() }.coerceIn(3, 5))
            }
            main.removeCallbacks(clearCaption); caption = transcript.trim()
            onCaption?.invoke(transcript, false)
        }
        if (sc.optBoolean("interrupted")) { responseActive = false; transcript = "" }
        if (sc.optBoolean("turnComplete")) {
            awaitingReply = false
            responseActive = false
            if (transcript.isNotEmpty()) {
                onCaption?.invoke(transcript, true); onReply?.invoke(transcript)
                val words = transcript.split(" ").count { it.isNotEmpty() }
                main.postDelayed(clearCaption, ((1.2 + words * 0.32).coerceIn(2.8, 12.0) * 1000 + 3000).toLong())
            }
            transcript = ""
            finishIfQuiet()
        }
    }

    private fun runTools(calls: List<JSONObject>) {
        var remaining = calls.size
        toolsRunning++
        val images = mutableListOf<String>()
        val responses = JSONArray()
        for (call in calls) {
            val name = call.optString("name")
            val id = call.optString("id")
            val arguments = call.optJSONObject("args")?.toString() ?: "{}"
            if (name == "go_to_sleep") sleepAfterReply = true
            val finish: (String, String?) -> Unit = finish@{ output, image ->
                if (socket == null) return@finish
                if (name.startsWith("focus_")) feedback = output
                if (name == "web_research") output.indexOf("\n---REPORT---\n").takeIf { it >= 0 }?.let { onReport?.invoke(output.substring(it + 14)) }
                responses.put(JSONObject().put("id", id).put("name", name).put("response", JSONObject().put("result", output)))
                image?.let { images += it }
                if (--remaining == 0) {
                    toolsRunning = maxOf(0, toolsRunning - 1)
                    // Screenshots go in as video frames before the results, so he can actually see the screen.
                    for (img in images) send(JSONObject().put("realtimeInput", JSONObject().put("video",
                        JSONObject().put("data", img).put("mimeType", "image/jpeg"))))
                    beginResponse()
                    send(JSONObject().put("toolResponse", JSONObject().put("functionResponses", responses)))
                }
            }
            runTool?.invoke(name, arguments, finish) ?: finish("The host isn't connected.", null)
        }
    }

    private fun finishIfQuiet() {
        if (pendingChirps != 0 || responseActive || toolsRunning != 0 || speaker.busy) return
        if (sleepAfterReply) { sleep(); return }
        if (reconnectWhenQuiet && !holding) { reconnect(); return }
        if (state == State.speaking || state == State.thinking) moveTo(if (holding) State.asking else State.listening)
        deliverCodexNotes()
    }

    // MARK: Audio

    @SuppressLint("MissingPermission")
    private fun startAudio(): Boolean {
        stopAudio()
        val min = AudioRecord.getMinBufferSize(MIC_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        if (min <= 0) return false
        // VOICE_COMMUNICATION applies the platform's echo cancellation, like iOS voice processing.
        val rec = runCatching { AudioRecord(MediaRecorder.AudioSource.VOICE_COMMUNICATION, MIC_RATE, AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT, maxOf(min, FRAME_BYTES * 4)) }.getOrNull() ?: return false
        if (rec.state != AudioRecord.STATE_INITIALIZED) { rec.release(); return false }
        if (AcousticEchoCanceler.isAvailable()) runCatching { AcousticEchoCanceler.create(rec.audioSessionId)?.enabled = true }
        rec.startRecording()
        recorder = rec
        micThread = Thread({
            val buf = ByteArray(FRAME_BYTES)
            while (recorder === rec) {
                val n = rec.read(buf, 0, buf.size)
                if (n <= 0) continue
                val data = buf.copyOf(n)
                var sum = 0.0
                for (i in 0 until n / 2) { val s = ((data[2 * i + 1].toInt() shl 8) or (data[2 * i].toInt() and 0xFF)) / 32768.0; sum += s * s }
                val rms = sqrt(sum / maxOf(1, n / 2))
                main.post {
                    if (recorder !== rec) return@post
                    inputLevel = min(1.0, rms * 12)
                    // Local speech: keep the whole held turn for the host; otherwise stream it to Gemini.
                    if (holding) turnAudio.append(data, !localSpeech && socketReady && activityOpen)?.let { appendAudio(it) }
                }
            }
        }, "bluey-mic").apply { start() }
        return true
    }

    private fun stopAudio() {
        val rec = recorder ?: return
        recorder = null
        runCatching { rec.stop() }; rec.release()
        micThread = null
    }

    private fun appendAudio(data: ByteArray) = send(JSONObject().put("realtimeInput", JSONObject().put("audio",
        JSONObject().put("data", Base64.getEncoder().encodeToString(data)).put("mimeType", "audio/pcm;rate=$MIC_RATE"))))

    /** Soft pentatonic boops (C6…E7 dropped an octave), same synthesis as iOS. */
    private fun chirp(syllables: Int) {
        val rate = CHIRP_RATE.toDouble()
        val scale = doubleArrayOf(1046.5, 1174.7, 1318.5, 1568.0, 1760.0, 2093.0, 2349.3, 2637.0)
        var index = Random.nextInt(1, 4)
        val samples = ArrayList<Float>()
        for (i in 0 until syllables) {
            if (i > 0) index = (index + listOf(-1, 1, 1, 2).random()).coerceIn(0, scale.size - 1)
            val note = scale[index] * 0.5
            val duration = if (i == syllables - 1) 0.13 else Random.nextDouble(0.07, 0.09)
            val count = (duration * rate).toInt()
            var phase = 0.0
            for (n in 0 until count) {
                val time = n / rate
                val t = n.toDouble() / count
                val scoop = 1 - 0.18 * exp(-time / 0.012)
                val wobble = if (i == syllables - 1) 1 + 0.012 * sin(time * 2 * Math.PI * 18) else 1.0
                phase += 2 * Math.PI * note * scoop * wobble / rate
                val envelope = min(1.0, time / 0.006) * exp(-t * 3.2) * (1 - t.pow(6))
                samples += ((sin(phase) + 0.12 * sin(2 * phase)) * envelope * 0.26).toFloat()
            }
            repeat((rate * 0.028).toInt()) { samples += 0f }
        }
        pendingChirps++
        val pcm = samples.toFloatArray()
        Thread({
            val t = track ?: AudioTrack.Builder()
                .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANT)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                .setAudioFormat(AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_FLOAT).setSampleRate(CHIRP_RATE)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
                .setTransferMode(AudioTrack.MODE_STREAM).build().also { track = it }
            synchronized(t) {
                t.setVolume(volume.toFloat()); t.play()
                var off = 0
                while (off < pcm.size) {
                    val n = min(1024, pcm.size - off)
                    var sum = 0f
                    for (k in off until off + n) sum += pcm[k] * pcm[k]
                    level = min(1.0, sqrt(sum / n).toDouble() * 5)
                    t.write(pcm, off, n, AudioTrack.WRITE_BLOCKING)
                    off += n
                }
            }
            main.post {
                pendingChirps = maxOf(0, pendingChirps - 1)
                if (pendingChirps == 0) level = 0.0
                finishIfQuiet()
            }
        }, "bluey-chirp").start()
    }

    companion object {
        private const val TAG = "BlueyVoice" // never logs audio, tokens or transcripts
        const val MIC_RATE = 16_000   // Gemini Live input
        const val CHIRP_RATE = 24_000
        const val FRAME_BYTES = 3200  // 100 ms PCM16 mono at 16 kHz
    }
}

/**
 * Port of Shared/VoiceTurnBuffer.swift: keeps a held utterance's start while the session connects.
 * Same durations as iOS (≥100 ms to send, ≤20 s buffered), at 16 kHz.
 */
class VoiceTurnBuffer(private val minBytes: Int = 3200, private val maxBytes: Int = 640_000) {
    var recordedBytes = 0; private set
    var overflowed = false; private set
    private val pending = mutableListOf<ByteArray>()
    private var pendingBytes = 0

    fun begin() { recordedBytes = 0; overflowed = false; pending.clear(); pendingBytes = 0 }
    val canCommit get() = !overflowed && recordedBytes >= minBytes

    fun append(data: ByteArray, ready: Boolean): ByteArray? {
        if (overflowed) return null
        recordedBytes += data.size
        if (ready) return data
        if (pendingBytes + data.size > maxBytes) { overflowed = true; pending.clear(); return null }
        pending += data; pendingBytes += data.size
        return null
    }

    fun connected(): List<ByteArray> {
        val data = pending.toList(); pending.clear(); pendingBytes = 0
        return if (overflowed) emptyList() else data
    }
}

/** Streams Gemini's spoken reply (PCM16 mono) to the speaker on its own thread and reports loudness for the mouth. */
class Speaker(private val onLevel: (Double) -> Unit) {
    var onDrained: (() -> Unit)? = null
    private val queue = java.util.concurrent.LinkedBlockingQueue<ByteArray>()
    private var track: AudioTrack? = null
    private var rate = 0
    private var worker: Thread? = null
    @Volatile private var generation = 0
    @Volatile var busy = false; private set

    fun setVolume(v: Float) { track?.setVolume(v) }

    @Synchronized fun play(pcm: ByteArray, sampleRate: Int, volume: Float) {
        if (track == null || rate != sampleRate) {
            track?.release()
            rate = sampleRate
            track = AudioTrack.Builder()
                .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANT)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                .setAudioFormat(AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT).setSampleRate(sampleRate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
                .setTransferMode(AudioTrack.MODE_STREAM).build()
        }
        track!!.setVolume(volume)
        busy = true
        queue.put(pcm)
        if (worker?.isAlive != true) {
            val gen = generation
            worker = Thread({ drain(gen) }, "bluey-speech").apply { start() }
        }
    }

    private fun drain(gen: Int) {
        val t = synchronized(this) { track } ?: return
        t.play()
        while (gen == generation) {
            val chunk = queue.poll(400, TimeUnit.MILLISECONDS) ?: break
            var sum = 0.0
            for (i in 0 until chunk.size / 2) {
                val s = ((chunk[2 * i + 1].toInt() shl 8) or (chunk[2 * i].toInt() and 0xFF)) / 32768.0; sum += s * s
            }
            onLevel(min(1.0, sqrt(sum / maxOf(1, chunk.size / 2)) * 5))
            t.write(chunk, 0, chunk.size, AudioTrack.WRITE_BLOCKING)
        }
        onLevel(0.0)
        if (gen == generation) { busy = false; onDrained?.invoke() }
    }

    /** Interrupt: drop what's queued and silence the track. */
    @Synchronized fun stop() {
        generation++
        queue.clear()
        track?.let { runCatching { it.pause(); it.flush() } }
        busy = false
        onLevel(0.0)
    }
}
