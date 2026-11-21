package co.visionairy.googly

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import co.visionairy.googly.proto.Packet
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

/** iOS TranscriptEntry.Kind raw values; the Mac's notes writer switches on them. */
enum class EntryKind { heard, asked, reply, report, transcript, codex }

data class TranscriptEntry(
    val id: String = UUID.randomUUID().toString().uppercase(),
    val kind: EntryKind,
    val text: String,
    val time: Long, // epoch millis
    val itemID: String? = null,
    val speaker: String? = null,
)

data class BlueySession(
    val id: String = UUID.randomUUID().toString().uppercase(),
    val started: Long,
    val ended: Long? = null,
    val entries: List<TranscriptEntry> = emptyList(),
    val notesPath: String? = null,
) {
    val questionCount get() = entries.count { it.kind == EntryKind.asked }
    val duration get() = ((ended ?: System.currentTimeMillis()) - started) / 1000.0
    val displayEntries: List<TranscriptEntry> get() {
        val properUntil = entries.filter { it.kind == EntryKind.transcript }.maxOfOrNull { it.time } ?: Long.MIN_VALUE
        return entries.filter { it.text.isNotEmpty() && !(it.kind == EntryKind.heard && it.time <= properUntil) }.sortedBy { it.time }
    }
    val summary get() = (entries.firstOrNull { it.kind == EntryKind.asked && it.text.isNotEmpty() }
        ?: displayEntries.firstOrNull { it.kind == EntryKind.transcript || it.kind == EntryKind.heard })?.text ?: "Nothing said yet"

    val exportText: String get() {
        val time = SimpleDateFormat("h:mm:ss a", Locale.getDefault())
        val lines = mutableListOf("Bluey session, ${SimpleDateFormat("d MMM yyyy, HH:mm", Locale.getDefault()).format(Date(started))}", "")
        for (e in displayEntries) {
            val who = when (e.kind) {
                EntryKind.transcript -> "Speaker ${e.speaker ?: "?"}"; EntryKind.heard -> "You"; EntryKind.asked -> "You asked"
                EntryKind.reply -> "Bluey"; EntryKind.report -> "Research"; EntryKind.codex -> "Codex"
            }
            lines += "[${time.format(Date(e.time))}] $who: ${e.text}"
        }
        return lines.joinToString("\n")
    }
}

/** Voice sessions on the phone, one private JSON file, synced to the Mac's notes writer (iOS SessionStore + NotesSync.send). */
class SessionStore(context: Context) {
    val sessions = mutableStateListOf<BlueySession>() // newest first
    var currentID by mutableStateOf<String?>(null); private set
    var onSync: ((List<BlueySession>) -> Unit)? = null

    private val file = File(context.filesDir, "sessions.json")
    private val main = Handler(Looper.getMainLooper())
    private val dirty = mutableSetOf<String>()
    private val saveWork = Runnable { save() }
    private val syncWork = Runnable {
        val changed = sessions.filter { it.id in dirty }
        dirty.clear()
        if (changed.isNotEmpty()) onSync?.invoke(changed)
    }

    init {
        runCatching { JSONArray(file.readText()) }.getOrNull()?.let { a ->
            for (i in 0 until a.length()) runCatching { decode(a.getJSONObject(i)) }.getOrNull()?.let { s ->
                // A session left open by a crash is closed at its last line.
                sessions.add(if (s.ended == null) s.copy(ended = s.entries.lastOrNull()?.time ?: s.started) else s)
            }
        }
    }

    val current get() = sessions.firstOrNull { it.id == currentID }

    fun start() {
        end()
        val s = BlueySession(started = System.currentTimeMillis())
        sessions.add(0, s); currentID = s.id; save()
    }

    fun end() {
        val id = currentID ?: return
        val i = sessions.indexOfFirst { it.id == id }.takeIf { it >= 0 } ?: return
        currentID = null
        val s = sessions[i]
        if (s.entries.all { it.text.isEmpty() } && System.currentTimeMillis() - s.started < 20_000) sessions.removeAt(i)
        else {
            sessions[i] = s.copy(ended = System.currentTimeMillis(), entries = s.entries.filter { it.text.isNotEmpty() })
            dirty += id; scheduleSync()
        }
        save()
    }

    fun placeholder(itemID: String, asked: Boolean) = update { s ->
        if (s.entries.any { it.itemID == itemID }) s
        else s.copy(entries = s.entries + TranscriptEntry(kind = if (asked) EntryKind.asked else EntryKind.heard, text = "", time = now(), itemID = itemID))
    }

    fun heard(itemID: String, text: String, asked: Boolean) {
        val t = text.trim()
        update { s ->
            val i = s.entries.indexOfFirst { it.itemID == itemID }
            when {
                i >= 0 -> s.copy(entries = s.entries.toMutableList().also {
                    it[i] = it[i].copy(text = t, kind = if (asked) EntryKind.asked else it[i].kind)
                })
                t.isNotEmpty() -> s.copy(entries = s.entries + TranscriptEntry(kind = if (asked) EntryKind.asked else EntryKind.heard, text = t, time = now(), itemID = itemID))
                else -> s
            }
        }
    }

    fun reply(text: String) = add(EntryKind.reply, text)
    fun report(text: String) = add(EntryKind.report, text)
    fun codex(text: String) { if (currentID != null) add(EntryKind.codex, text) }

    private fun add(kind: EntryKind, text: String) {
        val t = text.trim()
        if (t.isNotEmpty()) update { it.copy(entries = it.entries + TranscriptEntry(kind = kind, text = t, time = now())) }
    }

    fun setNotesPath(id: String, path: String) {
        val i = sessions.indexOfFirst { it.id == id }
        if (i < 0 || sessions[i].notesPath == path) return
        sessions[i] = sessions[i].copy(notesPath = path); scheduleSave()
    }

    fun recentText(limit: Int = 6000): String? {
        val text = current?.displayEntries?.filter { it.kind != EntryKind.report }
            ?.joinToString("\n") { (if (it.kind == EntryKind.reply) "Bluey: " else "") + it.text } ?: return null
        return text.ifEmpty { null }?.takeLast(limit)
    }

    fun resyncRecent() {
        val cutoff = System.currentTimeMillis() - 3 * 86_400_000L
        dirty += sessions.filter { it.started > cutoff }.map { it.id }
        scheduleSync()
    }

    fun delete(id: String) {
        if (id == currentID) currentID = null
        sessions.removeAll { it.id == id }; save()
    }

    private fun update(change: (BlueySession) -> BlueySession) {
        val id = currentID ?: return
        val i = sessions.indexOfFirst { it.id == id }.takeIf { it >= 0 } ?: return
        sessions[i] = change(sessions[i])
        dirty += id; scheduleSync(); scheduleSave()
    }

    private fun scheduleSync() { main.removeCallbacks(syncWork); main.postDelayed(syncWork, 6000) }
    private fun scheduleSave() { main.removeCallbacks(saveWork); main.postDelayed(saveWork, 1000) }

    private fun save() {
        main.removeCallbacks(saveWork)
        val a = JSONArray(); sessions.forEach { a.put(encode(it)) }
        val tmp = File(file.path + ".tmp"); tmp.writeText(a.toString()); tmp.renameTo(file)
    }

    private fun now() = System.currentTimeMillis()

    private fun encode(s: BlueySession) = JSONObject().put("id", s.id).put("started", s.started).put("ended", s.ended)
        .put("notesPath", s.notesPath).put("entries", JSONArray().apply {
            s.entries.forEach { e -> put(JSONObject().put("id", e.id).put("kind", e.kind.name).put("text", e.text)
                .put("time", e.time).put("itemID", e.itemID).put("speaker", e.speaker)) }
        })

    private fun decode(o: JSONObject): BlueySession {
        val a = o.getJSONArray("entries")
        return BlueySession(o.getString("id"), o.getLong("started"), if (o.isNull("ended")) null else o.getLong("ended"),
            List(a.length()) { i -> a.getJSONObject(i).let { e ->
                TranscriptEntry(e.getString("id"), EntryKind.valueOf(e.getString("kind")), e.getString("text"), e.getLong("time"),
                    e.optString("itemID").ifEmpty { null }, e.optString("speaker").ifEmpty { null })
            } }, o.optString("notesPath").ifEmpty { null })
    }

    companion object {
        /** iOS NotesSync.send: the Mac's `notes` request, times as Unix seconds. */
        fun notesPayload(s: BlueySession): String = JSONObject().apply {
            put("id", s.id); put("started", s.started / 1000.0); put("transcribing", 0)
            s.ended?.let { put("ended", it / 1000.0) }
            put("entries", JSONArray().apply {
                s.displayEntries.forEach { e ->
                    put(JSONObject().put("kind", e.kind.name).put("text", e.text).put("time", e.time / 1000.0).apply { e.speaker?.let { put("speaker", it) } })
                }
            })
        }.toString()

        fun sync(sessions: List<BlueySession>, store: SessionStore, link: MacLink) {
            if (!link.connected) return
            for (s in sessions) link.request(Packet(command = "notes", text = notesPayload(s))) { reply ->
                reply?.text?.let { store.setNotesPath(s.id, it) }
            }
        }
    }
}
