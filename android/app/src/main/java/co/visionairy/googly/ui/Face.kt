package co.visionairy.googly.ui

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.rotateRad
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.drawscope.withTransform
import co.visionairy.googly.proto.FaceState
import co.visionairy.googly.proto.Mood
import kotlin.math.PI
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random

private class Spring(var value: Double, val stiffness: Double = 200.0, val damping: Double = 0.7) {
    var velocity = 0.0
    fun step(target: Double, dt: Double) {
        val c = 2 * sqrt(stiffness) * damping
        velocity += (stiffness * (target - value) - c * velocity) * dt
        value += velocity * dt
    }
}

private fun rnd(a: Double, b: Double) = Random.nextDouble(a, b)

/** Port of iOS FaceAnimator: springs, saccades, blinks, hops. Times in seconds. */
class FaceAnimator {
    class Frame(
        val gazeX: Double, val gazeY: Double, val mood: Mood, val talk: Double, val closed: Double, val breathe: Double,
        val time: Double, val pupil: Double, val browLift: Double, val browTilt: Double, val lean: Double,
        val hop: Double, val blush: Double, val squint: Double,
    )

    private var target = FaceState()
    private var lastPacket = -100.0
    private val gazeX = Spring(0.0, 260.0, 0.82)
    private val gazeY = Spring(0.0, 260.0, 0.82)
    private val pupil = Spring(1.0, 160.0, 0.5)
    private val browLift = Spring(0.0, 180.0, 0.55)
    private val browTilt = Spring(0.0, 150.0, 0.6)
    private val lean = Spring(0.0, 60.0, 0.8)
    private val hop = Spring(0.0, 260.0, 0.35)
    private val blush = Spring(0.25, 40.0, 1.0)
    private val squint = Spring(0.0, 150.0, 0.7)
    private var talk = 0.0
    private var mood = Mood.listening
    private var blinkStart = -1.0
    private var doubleBlink = false
    private var nextBlink = 2.0
    private var lastTime: Double? = null
    private var nextSaccade = 0.0
    private var wanderX = 0.0; private var wanderY = -0.3
    private var jitterX = 0.0; private var jitterY = 0.0
    private var nextJitter = 0.0
    private var nextHop = 6.0

    var localMood: Mood? = null
    var localTalk: () -> Double = { 0.0 }
    var awake = false

    fun receive(face: FaceState, time: Double) { target = face; lastPacket = time }

    fun step(now: Double): Frame {
        val dt = min(now - (lastTime ?: now), 1.0 / 20)
        lastTime = now
        val live = now - lastPacket < 2.5
        val wantedMood = localMood ?: if (live) target.mood else Mood.listening
        if (wantedMood != mood) {
            mood = wantedMood
            blinkStart = now
            if (mood != Mood.sleepy && mood != Mood.resting) { hop.velocity += 260; pupil.velocity += 3 }
        }
        var wantX: Double; var wantY: Double
        if (live) { wantX = target.gazeX; wantY = target.gazeY } else {
            if (now > nextSaccade) { wanderX = rnd(-0.9, 0.9); wanderY = rnd(-0.9, 0.4); nextSaccade = now + rnd(0.6, 2.2) }
            wantX = wanderX; wantY = wanderY
        }
        if (mood == Mood.thinking) { wantX = 0.6 + 0.08 * sin(now * 1.3); wantY = -0.85 }
        if (now > nextJitter) {
            val amount = if (!awake) 0.015 else if (mood == Mood.talking) 0.07 else if (mood == Mood.thinking) 0.05 else 0.02
            jitterX = rnd(-amount, amount); jitterY = rnd(-amount, amount)
            nextJitter = now + rnd(0.5, 1.4)
        }
        gazeX.step(wantX + jitterX, dt); gazeY.step(wantY + jitterY, dt)

        var wantTalk = if (live) target.talk else if (localMood == Mood.talking) 0.5 + 0.5 * sin(now * 19) * sin(now * 7.3) else 0.0
        wantTalk = max(wantTalk, localTalk())
        talk += (wantTalk - talk) * min(1.0, dt * 25)

        var wPupil = 1.0; var wLift = 0.0; var wTilt = 0.0; var wBlush = 0.25; var wSquint = 0.0
        when (mood) {
            Mood.listening -> { wPupil = 1.12; wLift = 10.0 }
            Mood.talking -> { wPupil = 1.05; wLift = 6 + talk * 18; wTilt = 0.05 * sin(now * 2.3) }
            Mood.pointing -> { wPupil = 0.95; wLift = -4.0; wTilt = -0.14 }
            Mood.thinking -> { wPupil = 0.9; wLift = 4.0; wTilt = 0.22 }
            Mood.happy -> { wPupil = 1.2; wLift = 16.0; wBlush = 0.85; wSquint = 1.0 }
            Mood.resting -> { wPupil = 0.9; wLift = -8.0; wBlush = 0.15 }
            Mood.sleepy -> { wPupil = 0.88; wLift = -10.0; wTilt = 0.12; wBlush = 0.15 }
        }
        pupil.step(wPupil, dt); browLift.step(wLift, dt); browTilt.step(wTilt, dt)
        blush.step(wBlush, dt); squint.step(wSquint, dt); lean.step(-gazeX.value * 0.045, dt)

        if (now > nextHop) {
            if (talk < 0.05 && mood != Mood.sleepy && mood != Mood.resting) hop.velocity += rnd(180.0, 320.0)
            nextHop = now + rnd(7.0, 14.0)
        }
        hop.step(0.0, dt)

        val drowsy = mood == Mood.sleepy
        if (now > nextBlink) {
            blinkStart = now
            doubleBlink = !drowsy && Random.nextDouble() < 0.25
            nextBlink = now + if (drowsy) rnd(1.6, 3.0) else rnd(2.0, 5.0)
        }
        val p = (now - blinkStart) / (if (drowsy) 0.7 else 0.15)
        var closed = if (p in 0.0..1.0) sin(PI * p) else 0.0
        if (doubleBlink && p in 1.3..2.3) closed = sin(PI * (p - 1.3))

        return Frame(gazeX.value, gazeY.value, mood, talk, closed, sin(now * if (mood == Mood.resting) 1.1 else 1.8), now,
            pupil.value, browLift.value, browTilt.value, lean.value, hop.value, blush.value, squint.value.coerceIn(0.0, 1.0))
    }
}

val Berry1 = Color(0xFFA9BCFF); val Berry2 = Color(0xFF6C86F5); val Berry3 = Color(0xFF4254D6); val Berry4 = Color(0xFF2B2F8F)
val Nose = Color(0xFF1C1F66); val Ink = Color(0xFF17151F); val InkSoft = Color(0xFFB9B2CC); val Panel = Color(0xFF1E1B29)

/** CSS `border-radius: 52% 48% 46% 54% / 58% 56% 44% 42%` as cubic curves (iOS BlobShape). */
fun blobPath(r: Rect): Path {
    val w = r.width; val h = r.height; val k = 0.5523f
    val tlw = 0.52f * w; val tlh = 0.58f * h; val trw = 0.48f * w; val trh = 0.56f * h
    val brw = 0.46f * w; val brh = 0.44f * h; val blw = 0.54f * w; val blh = 0.42f * h
    return Path().apply {
        moveTo(r.left + tlw, r.top)
        lineTo(r.right - trw, r.top)
        cubicTo(r.right - trw * (1 - k), r.top, r.right, r.top + trh * (1 - k), r.right, r.top + trh)
        lineTo(r.right, r.bottom - brh)
        cubicTo(r.right, r.bottom - brh * (1 - k), r.right - brw * (1 - k), r.bottom, r.right - brw, r.bottom)
        lineTo(r.left + blw, r.bottom)
        cubicTo(r.left + blw * (1 - k), r.bottom, r.left, r.bottom - blh * (1 - k), r.left, r.bottom - blh)
        lineTo(r.left, r.top + tlh)
        cubicTo(r.left, r.top + tlh * (1 - k), r.left + tlw * (1 - k), r.top, r.left + tlw, r.top)
        close()
    }
}

fun blobBrush(r: Rect) = Brush.linearGradient(
    0f to Berry1, 0.34f to Berry2, 0.68f to Berry3, 1f to Berry4,
    start = Offset(r.left + 0.25f * r.width, r.top + 0.067f * r.height),
    end = Offset(r.left + 0.75f * r.width, r.top + 0.933f * r.height),
)

private fun crownPath(r: Rect) = Path().apply {
    val pts = listOf(30 to 4, 36 to 16, 52 to 12, 40 to 24, 46 to 36, 30 to 28, 14 to 36, 20 to 24, 8 to 12, 24 to 16)
    pts.forEachIndexed { i, (x, y) ->
        val px = r.left + x / 60f * r.width; val py = r.top + y / 40f * r.height
        if (i == 0) moveTo(px, py) else lineTo(px, py)
    }
    close()
}

private fun ellipse(r: Rect) = Path().apply { addOval(r) }

/** Full-screen face, redrawn every frame. */
@Composable
fun FaceCanvas(animator: FaceAnimator, modifier: Modifier = Modifier) {
    var frameNanos by remember { mutableLongStateOf(0L) }
    LaunchedEffect(Unit) { while (true) withFrameNanos { frameNanos = it } }
    Canvas(modifier) {
        val f = animator.step(frameNanos / 1e9)
        drawFace(f)
    }
}

private const val DESIGN_W = 844f
private const val DESIGN_H = 390f

private fun DrawScope.drawFace(f: FaceAnimator.Frame) {
    drawRect(Color.Black)
    val s = max(size.width / DESIGN_W, size.height / DESIGN_H)
    translate((size.width - DESIGN_W * s) / 2, size.height - DESIGN_H * s) {
        scale(s, s, pivot = Offset.Zero) { drawBody(f) }
    }
}

private fun DrawScope.drawBody(f: FaceAnimator.Frame) {
    val bounce = (-f.talk * 16 + f.breathe * 3 - f.hop).toFloat()
    val body = Rect(12f, 44f + bounce, 832f, 744f + bounce)
    val pivot = Offset(body.center.x, body.bottom)
    val stretch = 1 + (f.hop / 900).coerceIn(-0.03, 0.03).toFloat()
    withTransform({
        rotateRad(f.lean.toFloat(), pivot)
        scale(2 - stretch, stretch, pivot)
    }) {
        val blob = blobPath(body)
        val skin = blobBrush(body)
        val shine = Brush.radialGradient(listOf(Color.White.copy(alpha = 0.5f), Color.White.copy(alpha = 0f)),
            center = Offset(body.left + 246, body.top + 126), radius = 243f)
        fun fillSkin(p: Path) { drawPath(p, skin); drawPath(p, shine) }

        drawPath(blob, Berry3)
        drawPath(blob, skin)
        clipPath(blob) {
            drawPath(blob, shine)
            drawOval(Color.White.copy(alpha = 0.35f), Offset(body.left + 190, body.top + 40), Size(46f, 22f))
        }
        drawPath(crownPath(Rect(Offset(body.left + 368, body.top - 20 - f.browLift.toFloat() * 0.3f), Size(84f, 56f))), Nose)

        val eyeY = body.top + 157
        val eyes = listOf(Offset(body.left + 280, eyeY), Offset(body.left + 540, eyeY))
        val squash = (1 - f.talk * 0.12).toFloat()

        for ((i, c) in eyes.withIndex()) {
            val side = if (i == 0) -1f else 1f
            // Soft blush: a radial falloff stands in for the iOS blur filter.
            val cheek = Offset(c.x + side * 62, c.y + 117)
            val a = (0.25 + 0.45 * f.blush).toFloat()
            drawOval(Brush.radialGradient(listOf(Color(0xFFF3A6D8).copy(alpha = a), Color(0xFFF3A6D8).copy(alpha = 0f)), center = cheek, radius = 55f),
                Offset(cheek.x - 60, cheek.y - 35), Size(120f, 70f))
        }

        for ((i, c) in eyes.withIndex()) {
            val side = if (i == 0) -1f else 1f
            val browY = c.y - 112 - (f.browLift.coerceIn(-10.0, 18.0) * 0.7).toFloat()
            withTransform({
                translate(c.x + side * 6, browY)
                rotateRad((f.browTilt * side * -1 + if (f.mood == Mood.thinking && i == 1) -0.25 else 0.0).toFloat(), Offset.Zero)
            }) {
                drawPath(Path().apply { moveTo(-38f, 6f); quadraticTo(0f, -12f, 38f, 6f) }, Nose, style = Stroke(14f, cap = StrokeCap.Round))
            }

            when {
                f.mood == Mood.resting -> drawPath(Path().apply { moveTo(c.x - 62, c.y + 6); quadraticTo(c.x, c.y + 52, c.x + 62, c.y + 6) },
                    Ink, style = Stroke(18f, cap = StrokeCap.Round))
                f.mood == Mood.happy && f.squint > 0.6 -> drawPath(Path().apply { moveTo(c.x - 60, c.y + 34); quadraticTo(c.x, c.y - 54, c.x + 60, c.y + 34) },
                    Ink, style = Stroke(24f, cap = StrokeCap.Round))
                else -> {
                    val open = (max(0.06, 1 - f.closed) * squash).toFloat()
                    val white = Rect(c.x - 95, c.y - 95 * open, c.x + 95, c.y + 95 * open)
                    val whitePath = ellipse(white)
                    drawPath(whitePath, Color.White)
                    if (open <= 0.2f) continue
                    var gx = f.gazeX; var gy = f.gazeY
                    val len = hypot(gx, gy); if (len > 1) { gx /= len; gy /= len }
                    val reach = 50f
                    val r = (46 * f.pupil).toFloat()
                    var px = c.x + gx.toFloat() * reach - side * 3
                    var py = c.y + gy.toFloat() * reach * open
                    if (f.mood == Mood.sleepy) py = max(py, c.y) + 28
                    clipPath(whitePath) {
                        drawCircle(Ink, r, Offset(px, py))
                        drawOval(Color.White, Offset(px - r * 0.58f, py - r * 0.72f), Size(r * 0.56f, r * 0.56f))
                        drawOval(Color.White.copy(alpha = 0.85f), Offset(px + r * 0.28f, py + r * 0.22f), Size(r * 0.24f, r * 0.24f))
                        if (f.squint > 0.02) fillSkin(ellipse(Rect(Offset(c.x - 110, c.y + 95 * open - 70 * f.squint.toFloat()), Size(220f, 160f))))
                        if (f.mood == Mood.sleepy) {
                            val droop = (0.5 + 0.06 * sin(f.time * 1.3)).toFloat()
                            fillSkin(Path().apply { addRect(Rect(Offset(c.x - 100, white.top - 10), Size(200f, white.height * droop + 10))) })
                            drawLine(Nose.copy(alpha = 0.7f), Offset(c.x - 92, white.top + white.height * droop),
                                Offset(c.x + 92, white.top + white.height * droop), 8f, StrokeCap.Round)
                        }
                        if (f.mood == Mood.pointing) fillSkin(Path().apply { addRect(Rect(Offset(c.x - 100, white.top - 20), Size(200f, 40f))) })
                    }
                }
            }
        }

        if (f.mood == Mood.thinking) for (i in 0 until 3) {
            val wobble = (sin(f.time * 3 + i) * 4).toFloat()
            drawCircle(Color.White.copy(alpha = 1 - i * 0.3f), 8f, Offset(body.left + 698 + i * 26f, body.top + 48 - i * 12f + wobble))
        }
        if (f.mood == Mood.resting) for (i in 0 until 3) {
            // Little z's: three short strokes each, so no font is needed in the draw loop.
            val phase = ((f.time * 0.35 + i / 3.0) % 1.0)
            val zs = 26f + i * 8f
            val x = body.left + 660 + phase.toFloat() * 70 + (sin(phase * 6) * 8).toFloat()
            val y = body.top + 90 - phase.toFloat() * 110
            val col = Color.White.copy(alpha = (0.9 * sin(PI * phase)).toFloat().coerceIn(0f, 1f))
            drawPath(Path().apply { moveTo(x - zs / 3, y - zs / 3); lineTo(x + zs / 3, y - zs / 3); lineTo(x - zs / 3, y + zs / 3); lineTo(x + zs / 3, y + zs / 3) },
                col, style = Stroke(zs / 7, cap = StrokeCap.Round))
        }

        val noseW = (60 - f.talk * 8).toFloat()
        val noseH = (38 + f.talk * 34).toFloat()
        val nose = Rect(Offset(body.left + 410 - noseW / 2, body.top + 272 - f.talk.toFloat() * 6), Size(noseW, noseH))
        if (f.mood == Mood.happy && f.talk < 0.1) {
            drawPath(Path().apply {
                moveTo(nose.left - 8, nose.top + 8); quadraticTo(nose.center.x, nose.top + 58, nose.right + 8, nose.top + 8); close()
            }, Nose)
        } else {
            drawOval(Nose, nose.topLeft, nose.size)
            if (f.talk > 0.25) drawOval(Color(0xFFE58BC4).copy(alpha = 0.9f),
                Offset(nose.center.x - noseW * 0.28f, nose.bottom - noseH * 0.38f), Size(noseW * 0.56f, noseH * 0.3f))
        }
    }
}
