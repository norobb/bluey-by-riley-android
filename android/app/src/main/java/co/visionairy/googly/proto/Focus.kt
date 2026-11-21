package co.visionairy.googly.proto

import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

/** Port of Shared/FocusSession.swift. Dates are Swift's default Codable form: seconds since 2001-01-01. */
enum class FocusActivity(val raw: String) {
    onTask("on_task"), offTask("off_task"), uncertain("uncertain"), unavailable("unavailable"), paused("paused");
    companion object { fun of(raw: String?) = entries.firstOrNull { it.raw == raw } }
}

data class FocusCheck(
    val id: String,
    val elapsed: Double,
    val activity: FocusActivity,
    val probability: Double = 0.0,
    val confidence: Double = 0.0,
    val probabilities: Map<String, Double>? = null,
    val sampleDuration: Double? = null,
    val nudged: Boolean = false,
) {
    fun estimate(category: FocusActivity): Double? {
        val graded = setOf(FocusActivity.onTask, FocusActivity.offTask, FocusActivity.uncertain)
        if (activity !in graded || category !in graded) return null
        // Older checks retained only P(off_task). Never infer P(on_task) from its complement.
        val value = probabilities?.get(category.raw) ?: (if (category == FocusActivity.offTask) probability else null)
        return value?.takeIf { it.isFinite() && it in 0.0..1.0 }
    }

    companion object {
        fun fromJson(o: JSONObject) = FocusCheck(
            id = o.optString("id"),
            elapsed = o.getDouble("elapsed"),
            activity = FocusActivity.of(o.getString("activity")) ?: throw IllegalArgumentException("activity"),
            probability = o.getDouble("probability"),
            confidence = o.getDouble("confidence"),
            probabilities = o.optJSONObject("probabilities")?.let { p -> p.keys().asSequence().associateWith { p.getDouble(it) } },
            sampleDuration = if (o.isNull("sampleDuration")) null else o.getDouble("sampleDuration"),
            nudged = o.optBoolean("nudged", false),
        )
    }
}

enum class FocusStatus { running, paused, ended }

data class FocusSession(
    val id: String,
    val task: String,
    val duration: Double,
    val startedAt: Double, // Apple reference-date seconds
    val elapsed: Double,
    val status: FocusStatus,
    val detail: String,
    val checks: List<FocusCheck>,
    val developerMode: Boolean?,
    val usedDeveloperMode: Boolean?,
    val realElapsed: Double?,
) {
    val isDeveloperMode get() = developerMode == true
    val clockRate get() = if (isDeveloperMode) 4.0 else 1.0
    val checkInterval get() = if (isDeveloperMode) 10.0 else 30.0
    val realActiveElapsed get() = realElapsed ?: elapsed
    val remaining get() = max(0.0, duration - elapsed)
    val startedAtMillis get() = ((startedAt + APPLE_EPOCH_OFFSET) * 1000).toLong()

    companion object {
        /** Seconds between 1970-01-01 and 2001-01-01. */
        const val APPLE_EPOCH_OFFSET = 978_307_200.0

        fun clock(seconds: Double): String {
            val n = max(0, ceil(seconds).toInt())
            return "%02d:%02d".format(n / 60, n % 60)
        }

        fun fromJson(o: JSONObject) = FocusSession(
            id = o.getString("id"),
            task = o.getString("task"),
            duration = o.getDouble("duration"),
            startedAt = o.getDouble("startedAt"),
            elapsed = o.getDouble("elapsed"),
            status = FocusStatus.valueOf(o.getString("status")),
            detail = o.getString("detail"),
            checks = o.getJSONArray("checks").let { a -> List(a.length()) { FocusCheck.fromJson(a.getJSONObject(it)) } },
            developerMode = if (o.isNull("developerMode")) null else o.getBoolean("developerMode"),
            usedDeveloperMode = if (o.isNull("usedDeveloperMode")) null else o.getBoolean("usedDeveloperMode"),
            realElapsed = if (o.isNull("realElapsed")) null else o.getDouble("realElapsed"),
        )

        fun listFromJson(a: JSONArray) = List(a.length()) { fromJson(a.getJSONObject(it)) }
    }
}

data class FocusSync(val current: FocusSession?, val history: List<FocusSession>, val revision: Int, val developerMode: Boolean?) {
    companion object {
        fun decode(text: String): FocusSync? = runCatching {
            val o = JSONObject(text)
            o.getDouble("sentAt") // required by the Swift decoder
            FocusSync(
                current = if (o.isNull("current")) null else FocusSession.fromJson(o.getJSONObject("current")),
                history = FocusSession.listFromJson(o.getJSONArray("history")),
                revision = o.getInt("revision"),
                developerMode = if (o.isNull("developerMode")) null else o.getBoolean("developerMode"),
            )
        }.getOrNull()
    }
}

/** Mac-side nudge evidence policy; kept here so the Linux port and tests share one reference. */
class FocusNudgePolicy(private val maximumGap: Double = 45.0, private val developerMode: Boolean = false) {
    private val run = mutableListOf<FocusCheck>()
    private var lastNudge = Double.NEGATIVE_INFINITY

    fun reset() = run.clear()

    fun observe(check: FocusCheck, age: Double): Boolean {
        if (!(age >= 0 && age <= 20 && check.elapsed.isFinite() && check.activity == FocusActivity.offTask &&
                check.probability.isFinite() && check.confidence.isFinite() &&
                check.probability in 0.5..1.0 && check.confidence in 0.0..1.0)) { reset(); return false }
        run.lastOrNull()?.let { last ->
            if (check.elapsed <= last.elapsed) { reset(); return false }
            if (check.elapsed - last.elapsed > maximumGap) reset()
        }
        run.add(check)
        val strength = run.sumOf { it.probability } / run.size
        val minimum = if (developerMode) 40.0 else 120.0
        val maximum = if (developerMode) 80.0 else 240.0
        val required = if (strength >= 0.95) minimum else maximum - max(0.0, strength - 0.5) / 0.45 * (maximum - minimum)
        if (run.size < 2 || check.elapsed - run.first().elapsed < max(minimum, required) || check.elapsed - lastNudge < 120) return false
        lastNudge = check.elapsed; reset(); return true
    }
}

data class FocusDecision(val activity: FocusActivity, val probability: Double, val confidence: Double, val probabilities: Map<String, Double>) {
    companion object {
        private val CHOICES = setOf("on_task", "off_task", "uncertain")

        /** Throws IllegalArgumentException for anything the Swift decoder rejects. */
        fun decode(text: String): FocusDecision {
            fun bad(): Nothing = throw IllegalArgumentException("Decisions returned an unsupported or malformed answer. This check was skipped.")
            fun num(v: Any?): Double? = (v as? Number)?.toDouble()
            val json = runCatching { JSONObject(text) }.getOrNull() ?: bad()
            val answers = json.optJSONArray("answers") ?: bad()
            val a = (0 until answers.length()).mapNotNull { answers.optJSONObject(it) }.firstOrNull { it.opt("name") == "activity" } ?: bad()
            if (a.opt("type") != "choice") bad()
            val activity = FocusActivity.of(a.opt("choice") as? String) ?: bad()
            if (activity.raw !in CHOICES) bad()
            val confidence = num(a.opt("confidence"))?.takeIf { it.isFinite() && it in 0.0..1.0 } ?: bad()
            val ps = a.optJSONArray("probabilities")?.takeIf { it.length() == 3 } ?: bad()
            val values = mutableMapOf<String, Double>()
            for (i in 0 until ps.length()) {
                val p = ps.optJSONObject(i) ?: bad()
                val v = p.opt("value") as? String ?: bad()
                if (v !in CHOICES || v in values) bad()
                values[v] = num(p.opt("probability"))?.takeIf { it.isFinite() && it in 0.0..1.0 } ?: bad()
            }
            if (abs(values.values.sum() - 1) >= 0.02) bad()
            val off = values["off_task"] ?: bad()
            return FocusDecision(activity, off, confidence, values)
        }
    }
}

internal fun clamp(v: Double, lo: Double, hi: Double) = min(hi, max(lo, v))
