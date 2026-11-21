package co.visionairy.googly

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import co.visionairy.googly.proto.FocusSession
import co.visionairy.googly.proto.FocusStatus
import co.visionairy.googly.proto.FocusSync
import co.visionairy.googly.proto.Packet
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** Renders the Mac's authoritative focus snapshots and sends commands (iOS FocusClient). */
class FocusClient(context: Context) {
    var current by mutableStateOf<FocusSession?>(null); private set
    var history by mutableStateOf<List<FocusSession>>(emptyList()); private set
    var fresh by mutableStateOf(false); private set
    var developerMode by mutableStateOf(false); private set
    var nudgeText by mutableStateOf(""); private set
    var message by mutableStateOf("")
    var onFinished: (() -> Unit)? = null

    private var revision = -1
    private var receivedAt = 0L
    private var nudgeToken = 0
    private var link: MacLink? = null
    private val main = Handler(Looper.getMainLooper())
    private val file = File(context.filesDir, "bluey-focus-history.json")

    init {
        // Stored as the Mac sent it, so it stays decodable by the same code.
        history = runCatching { FocusSession.listFromJson(JSONArray(file.readText())) }.getOrDefault(emptyList())
    }

    private val tick = object : Runnable {
        override fun run() {
            if (link?.connected == true) link?.send(Packet(command = "focusPing"))
            if (SystemClock.elapsedRealtime() - receivedAt > 5000) fresh = false
            main.postDelayed(this, 1000)
        }
    }

    fun attach(link: MacLink) {
        this.link = link
        main.removeCallbacks(tick); main.post(tick)
    }

    fun connectionChanged(connected: Boolean) {
        fresh = false; revision = -1
        if (connected) link?.send(Packet(command = "focusSync"))
    }

    fun receive(text: String) {
        val state = FocusSync.decode(text) ?: return
        if (state.revision <= revision) return
        val cur = current
        val finished = cur != null && cur.id == state.current?.id && cur.status != FocusStatus.ended && state.current.status == FocusStatus.ended
        revision = state.revision; receivedAt = SystemClock.elapsedRealtime(); fresh = true
        if (cur?.id != state.current?.id) nudgeText = ""
        current = state.current; history = state.history
        developerMode = state.developerMode ?: false
        runCatching { JSONObject(text).optJSONArray("history")?.let { file.writeText(it.toString()) } }
        if (finished) onFinished?.invoke()
    }

    fun receivedNudge(text: String) {
        nudgeText = text
        val token = ++nudgeToken
        main.postDelayed({ if (nudgeToken == token) nudgeText = "" }, 10_000)
    }

    fun command(command: String, task: String? = null, minutes: Double = 30.0, developerMode: Boolean? = null) {
        val link = link
        if (link == null || !link.connected) { message = "Connect your paired computer first."; return }
        val args = JSONObject().put("task", task ?: "").put("minutes", minutes)
        developerMode?.let { args.put("developerMode", it) }
        link.request(Packet(command = command, text = args.toString())) { reply ->
            message = reply?.text ?: "The computer didn't answer. Monitoring will pause if disconnected."
        }
    }
}
