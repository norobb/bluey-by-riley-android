package co.visionairy.googly.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.*
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import co.visionairy.googly.BlueySession
import co.visionairy.googly.EntryKind
import co.visionairy.googly.FocusClient
import co.visionairy.googly.LiveVoice
import co.visionairy.googly.MacLink
import co.visionairy.googly.R
import co.visionairy.googly.SessionStore
import co.visionairy.googly.TranscriptEntry
import co.visionairy.googly.proto.FocusActivity
import co.visionairy.googly.proto.FocusCheck
import co.visionairy.googly.proto.FocusSession
import co.visionairy.googly.proto.FocusStatus
import kotlinx.coroutines.delay
import java.text.DateFormat
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import kotlin.math.PI
import kotlin.math.sin

// MARK: Tokens. Quiet ink-blue neutrals; the blueberry face and Bluey's white speech bubbles carry the colour.

val Fredoka = FontFamily(Font(R.font.fredoka, FontWeight.Bold))
val PlexSans = FontFamily(Font(R.font.plex_sans))
val PlexMono = FontFamily(Font(R.font.plex_mono))

object Ui {
    val Bg = Color(0xFF0E0E12)
    val Surface = Color(0xFF17171D)
    val Raised = Color(0xFF20202A)
    val Hairline = Color(0x14FFFFFF)
    val Text1 = Color(0xFFF2F1F6)
    val Text2 = Color(0xFFB4B2C2)
    val Text3 = Color(0xFF7D7B8C)
    val Accent = Berry2
    val Good = Color(0xFF5FBF8A)
    val Warn = Color(0xFFEBAC73)
    val Danger = Color(0xFFE5677F)
    val Control = RoundedCornerShape(10.dp)
    val Card = RoundedCornerShape(14.dp)
}

private fun display(size: Int) = TextStyle(fontFamily = Fredoka, fontWeight = FontWeight.Bold, fontSize = size.sp, lineHeight = (size * 1.2).sp)
private fun body(size: Int, weight: FontWeight = FontWeight.Normal) = TextStyle(fontFamily = PlexSans, fontSize = size.sp, fontWeight = weight, lineHeight = (size * 1.45).sp)
private fun mono(size: Int) = TextStyle(fontFamily = PlexMono, fontSize = size.sp, fontFeatureSettings = "tnum")

private fun Double.percent() = if ((this * 1000).toInt() % 10 != 0) "%.1f%%".format(this * 100) else "%.0f%%".format(this * 100)
private fun time(ms: Long) = DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(ms))
private fun dayLabel(ms: Long): String {
    val day = Calendar.getInstance().apply { timeInMillis = ms }
    val today = Calendar.getInstance()
    fun same(a: Calendar, b: Calendar) = a.get(Calendar.YEAR) == b.get(Calendar.YEAR) && a.get(Calendar.DAY_OF_YEAR) == b.get(Calendar.DAY_OF_YEAR)
    if (same(day, today)) return "Today"
    today.add(Calendar.DAY_OF_YEAR, -1)
    if (same(day, today)) return "Yesterday"
    return SimpleDateFormat("EEEE, d MMMM", Locale.getDefault()).format(Date(ms))
}
private fun durationText(seconds: Double): String {
    val s = seconds.toInt()
    return if (s >= 3600) "%d:%02d:%02d".format(s / 3600, s / 60 % 60, s % 60) else "%d:%02d".format(s / 60, s % 60)
}

// MARK: Shared controls

@Composable
private fun PrimaryButton(text: String, modifier: Modifier = Modifier, enabled: Boolean = true, icon: ImageVector? = null, onClick: () -> Unit) {
    Button(onClick, modifier.heightIn(min = 44.dp), enabled = enabled, shape = Ui.Control,
        colors = ButtonDefaults.buttonColors(containerColor = Ui.Text1, contentColor = Ink, disabledContainerColor = Ui.Raised, disabledContentColor = Ui.Text3)) {
        icon?.let { Icon(it, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)) }
        Text(text, style = body(15, FontWeight.Medium))
    }
}

@Composable
private fun SecondaryButton(text: String, modifier: Modifier = Modifier, enabled: Boolean = true, icon: ImageVector? = null, onClick: () -> Unit) {
    OutlinedButton(onClick, modifier.heightIn(min = 44.dp), enabled = enabled, shape = Ui.Control,
        border = androidx.compose.foundation.BorderStroke(1.dp, Ui.Hairline),
        colors = ButtonDefaults.outlinedButtonColors(containerColor = Ui.Raised, contentColor = Ui.Text1, disabledContentColor = Ui.Text3)) {
        icon?.let { Icon(it, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)) }
        Text(text, style = body(15, FontWeight.Medium))
    }
}

@Composable
private fun IconAction(icon: ImageVector, label: String, enabled: Boolean = true, tint: Color = Ui.Text2, onClick: () -> Unit) {
    IconButton(onClick, Modifier.size(44.dp).semantics { contentDescription = label }, enabled = enabled) {
        Icon(icon, null, tint = if (enabled) tint else Ui.Text3.copy(alpha = 0.5f), modifier = Modifier.size(20.dp))
    }
}

@Composable
private fun SectionLabel(text: String, modifier: Modifier = Modifier) =
    Text(text, modifier.semantics { heading() }, style = body(13, FontWeight.Medium), color = Ui.Text3)

@Composable
private fun NavRow(icon: ImageVector, label: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clip(Ui.Control).clickable(role = Role.Button, onClick = onClick).heightIn(min = 44.dp).padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(icon, null, tint = Ui.Text2, modifier = Modifier.size(18.dp))
        Text(label, style = body(15), color = Ui.Text1, modifier = Modifier.weight(1f))
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = Ui.Text3, modifier = Modifier.size(18.dp))
    }
}

@Composable
private fun StatusDot(color: Color) = Box(Modifier.size(8.dp).background(color, CircleShape))

@Composable
private fun TopBar(title: String, subtitle: String? = null, onBack: () -> Unit, actions: @Composable RowScope.() -> Unit = {}) {
    Row(Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(start = 12.dp, end = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        IconAction(Icons.AutoMirrored.Filled.ArrowBack, "Back", tint = Ui.Text1, onClick = onBack)
        Column(Modifier.weight(1f).padding(start = 4.dp)) {
            Text(title, style = display(22), color = Ui.Text1, modifier = Modifier.semantics { heading() })
            subtitle?.let { Text(it, style = mono(12), color = Ui.Text3) }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp), content = actions)
    }
    HorizontalDivider(color = Ui.Hairline)
}

/** Overlay layer inside the activity window; Dialog windows get clipped by cutouts in immersive landscape. */
@Composable
fun FullScreen(onDismiss: () -> Unit, content: @Composable () -> Unit) {
    BackHandler(onBack = onDismiss)
    Surface(Modifier.fillMaxSize().pointerInput(Unit) { detectTapGestures { } }, color = Ui.Bg, contentColor = Ui.Text1) {
        Box(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.displayCutout)) { content() }
    }
}

// MARK: Face overlays

/** Solid border by voice state (iOS ModeIndicator). */
@Composable
fun ModeIndicator(state: LiveVoice.State) {
    val color = when (state) {
        LiveVoice.State.asleep -> Color.Transparent
        LiveVoice.State.waking -> Color(0xFFFFD66B)
        LiveVoice.State.listening, LiveVoice.State.asking -> Color(0xFF4F8BFF)
        LiveVoice.State.thinking -> Color(0xFFC79BFF)
        LiveVoice.State.speaking -> Color(0xFFFF9AD0)
    }
    val border by animateFloatAsState(when (state) {
        LiveVoice.State.asleep -> 0f; LiveVoice.State.waking -> 6f; LiveVoice.State.listening -> 10f
        LiveVoice.State.asking -> 16f; else -> 8f
    }, tween(250), label = "border")
    val pulse = when (state) { LiveVoice.State.waking -> 1.6; LiveVoice.State.asking -> 1.2; LiveVoice.State.thinking -> 1.1; else -> 0.0 }
    var t by remember { mutableLongStateOf(0L) }
    LaunchedEffect(pulse) { while (pulse > 0) withFrameNanos { t = it } }
    Canvas(Modifier.fillMaxSize()) {
        if (border <= 0f) return@Canvas
        val wave = if (pulse > 0) 0.5 + 0.5 * sin(t / 1e9 * pulse * 2 * PI) else 1.0
        val w = border.dp.toPx()
        drawRoundRect(color, Offset(w / 2, w / 2), Size(size.width - w, size.height - w), CornerRadius(40.dp.toPx()), Stroke(w),
            alpha = if (pulse > 0) (0.65 + 0.35 * wave).toFloat() else 1f)
    }
}

/** His reply as a speech bubble above his head, the same white bubble the computer shows. */
@Composable
fun CaptionBubble(live: LiveVoice) {
    val text = live.caption
    Box(Modifier.fillMaxSize().padding(top = 72.dp), contentAlignment = Alignment.TopCenter) {
        AnimatedVisibility(text.isNotEmpty(), enter = fadeIn(tween(160)) + slideInVertically(tween(160)) { it / 6 }, exit = fadeOut(tween(160))) {
            Text(text, Modifier.widthIn(max = 520.dp).background(Color.White, RoundedCornerShape(20.dp)).padding(horizontal = 20.dp, vertical = 12.dp)
                .semantics { contentDescription = "Bluey says: $text" },
                style = display(20), color = Ink, maxLines = 4, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
        }
    }
}

@Composable
private fun RoundIcon(icon: ImageVector, label: String, enabled: Boolean = true, tint: Color = Color.White, bg: Float = 0.09f, onClick: (() -> Unit)?) {
    Box(Modifier.size(44.dp).then(if (onClick != null) Modifier.clip(CircleShape).clickable(enabled = enabled, role = Role.Button, onClick = onClick) else Modifier)
        .semantics { contentDescription = label }, contentAlignment = Alignment.Center) {
        Box(Modifier.size(36.dp).background(Color.White.copy(alpha = bg), CircleShape), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = tint.copy(alpha = if (enabled) tint.alpha else 0.35f), modifier = Modifier.size(18.dp))
        }
    }
}

@Composable
fun FocusFaceHUD(focus: FocusClient, link: MacLink, live: LiveVoice, open: () -> Unit, pair: () -> Unit) {
    val current = focus.current?.takeIf { it.status != FocusStatus.ended }
    val status = when {
        !link.connected -> "Pair your computer to focus together"
        current == null -> "Hold Bluey and describe a task"
        !focus.fresh -> "Connection lost · monitoring will pause"
        current.status == FocusStatus.paused -> "Paused"
        else -> current.checks.lastOrNull { it.activity != FocusActivity.paused }?.let { c ->
            when (c.activity) {
                FocusActivity.offTask -> "Off task · ${c.probability.percent()} estimate${if (c.nudged) " · nudged" else ""}"
                FocusActivity.onTask -> "On task"
                FocusActivity.uncertain -> "Not sure yet · checking again"
                else -> "Last check unavailable · trying again"
            }
        } ?: "Focusing together"
    }
    val feedback = focus.nudgeText.ifEmpty { live.feedback }
    Box(Modifier.fillMaxSize().padding(horizontal = 24.dp, vertical = 20.dp)) {
        Column(Modifier.align(Alignment.TopStart).widthIn(max = 360.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(current?.task ?: "What's the mission?", style = display(22), color = Color.White, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(status, style = mono(11), color = Color.White.copy(alpha = 0.7f))
            if (focus.developerMode) Text("Developer mode · 4× clock · checks every 10 s", style = mono(11), color = Color.White.copy(alpha = 0.7f))
            if (feedback.isNotEmpty()) Text(feedback, style = body(13), color = Color.White.copy(alpha = 0.85f), maxLines = 2, overflow = TextOverflow.Ellipsis)
            if (live.state == LiveVoice.State.asking) Box(Modifier.padding(top = 4.dp).size((24 + live.inputLevel * 96).dp, 4.dp).background(Color.White, CircleShape))
        }
        Row(Modifier.align(Alignment.BottomStart), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            if (!link.connected) RoundIcon(Icons.Filled.QrCodeScanner, "Pair computer", onClick = pair)
            else if (current != null) {
                val running = current.status == FocusStatus.running
                RoundIcon(if (running) Icons.Filled.Pause else Icons.Filled.PlayArrow, if (running) "Pause focus" else "Resume focus", focus.fresh) {
                    focus.command(if (running) "focusPause" else "focusResume")
                }
                RoundIcon(Icons.Filled.Stop, "End focus", focus.fresh) { focus.command("focusEnd") }
            }
            RoundIcon(Icons.Filled.CenterFocusStrong, "Focus sessions", onClick = open)
            val (icon, label) = when (live.state) {
                LiveVoice.State.asleep -> Icons.Filled.MicOff to "Hold Bluey to speak"
                LiveVoice.State.waking -> Icons.Filled.Sync to "Voice connecting"
                LiveVoice.State.listening -> Icons.Filled.Hearing to "Listening. Hold Bluey to ask"
                LiveVoice.State.asking -> Icons.Filled.Mic to "Recording your request"
                LiveVoice.State.thinking -> Icons.Filled.MoreHoriz to "Thinking"
                LiveVoice.State.speaking -> Icons.Filled.RecordVoiceOver to "Replying"
            }
            RoundIcon(icon, label, tint = if (live.state == LiveVoice.State.asleep) Color.White.copy(alpha = 0.4f) else Color.White, bg = 0.07f, onClick = null)
        }
        val countdown = current?.remaining ?: 1800.0
        Text(FocusSession.clock(countdown), Modifier.align(Alignment.BottomEnd).semantics { contentDescription = "Time remaining ${FocusSession.clock(countdown)}" },
            style = TextStyle(fontFamily = Fredoka, fontSize = 76.sp, fontWeight = FontWeight.Bold, fontFeatureSettings = "tnum"), color = Color.White, maxLines = 1)
    }
}

/** Speaker button top-right: volume, say hi, choose computer (iOS SoundButton). */
@Composable
fun SoundButton(link: MacLink, live: LiveVoice) {
    var open by remember { mutableStateOf(false) }
    var volume by remember { mutableDoubleStateOf(live.volume) }
    var lastTouch by remember { mutableLongStateOf(0L) }
    LaunchedEffect(lastTouch) { delay(6000); open = false }
    Column(Modifier.fillMaxSize().padding(top = 12.dp, end = 16.dp), horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        val icon = when { open -> Icons.Filled.Close; volume < 0.01 -> Icons.AutoMirrored.Filled.VolumeOff; volume < 0.5 -> Icons.AutoMirrored.Filled.VolumeDown; else -> Icons.AutoMirrored.Filled.VolumeUp }
        RoundIcon(icon, if (open) "Close sound settings" else "Sound settings", tint = Color.White.copy(alpha = if (open) 0.9f else 0.4f), bg = if (open) 0.14f else 0.06f) {
            open = !open; lastTouch = System.nanoTime()
        }
        AnimatedVisibility(open, enter = fadeIn(tween(160)), exit = fadeOut(tween(160))) {
            Column(Modifier.width(272.dp).background(Ui.Surface.copy(alpha = 0.97f), Ui.Card).border(1.dp, Ui.Hairline, Ui.Card).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)) {
                VolumeControls(live, volume, { volume = it; lastTouch = System.nanoTime() })
                PrimaryButton(if (live.state == LiveVoice.State.asleep) "Wake him up" else "Say hi", Modifier.fillMaxWidth(), enabled = link.connected) {
                    live.sayHi(); lastTouch = System.nanoTime()
                }
                ComputerChooser(link) { lastTouch = System.nanoTime() }
                if (!link.connected) Text("Connect to your computer to talk to him", style = body(13), color = Ui.Text3)
            }
        }
    }
}

@Composable
private fun VolumeControls(live: LiveVoice, volume: Double, changed: (Double) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Volume", style = body(14), color = Ui.Text1, modifier = Modifier.weight(1f))
            Text("${(volume * 100).toInt()}%", style = mono(13), color = Ui.Text2)
        }
        Slider(volume.toFloat(), { changed(it.toDouble()); live.volume = it.toDouble() }, Modifier.height(32.dp).semantics { contentDescription = "Volume" },
            colors = SliderDefaults.colors(thumbColor = Ui.Text1, activeTrackColor = Ui.Accent, inactiveTrackColor = Ui.Raised))
    }
}

@Composable
private fun ComputerChooser(link: MacLink, touched: () -> Unit = {}) {
    if (link.macs.size <= 1) return
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        SectionLabel("Computer")
        link.macs.forEach { name ->
            Row(Modifier.fillMaxWidth().heightIn(min = 40.dp).clip(Ui.Control).clickable { link.choose(name); touched() }.padding(horizontal = 4.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Text(name, style = body(14), color = Ui.Text1, maxLines = 1, modifier = Modifier.weight(1f))
                if (name == link.currentMac) Icon(if (link.connected) Icons.Filled.Check else Icons.Filled.MoreHoriz, null, tint = Ui.Accent, modifier = Modifier.size(18.dp))
            }
        }
    }
}

/** Until a paired computer is found: sleepy blob and how to pair (iOS PairingView). */
@Composable
fun PairingOverlay(onPair: () -> Unit) {
    Row(Modifier.fillMaxSize().background(Color.Black).padding(horizontal = 72.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(56.dp, Alignment.CenterHorizontally)) {
        MiniBluey(Modifier.size(220.dp, 190.dp), sleepy = true)
        Column(Modifier.widthIn(max = 400.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text("Your little focus friend", style = display(32), color = Ui.Text1)
            Text("Open Bluey on your computer and choose Pair phone (QR) in its menu. Scan once, and he reconnects securely on the same Wi‑Fi.",
                style = body(16), color = Ui.Text2)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                CircularProgressIndicator(Modifier.size(16.dp), color = Berry1, strokeWidth = 2.dp)
                Text("Looking for your computer", style = mono(13), color = Ui.Text3)
            }
            PrimaryButton("Scan pairing code", icon = Icons.Filled.QrCodeScanner, onClick = onPair)
        }
    }
}

/** The blob with two googly eyes; the sleepy variant has closed eyes. */
@Composable
fun MiniBluey(modifier: Modifier, sleepy: Boolean = false) {
    Canvas(modifier) {
        val r = Rect(Offset.Zero, size)
        drawPath(blobPath(r), blobBrush(r))
        val w = size.width
        val cy = size.height * 0.46f
        for (side in listOf(-1, 1)) {
            val cx = w / 2 + side * w * 0.18f
            if (sleepy) drawLine(Ink, Offset(cx - w * 0.1f, cy), Offset(cx + w * 0.1f, cy), w * 0.03f, StrokeCap.Round)
            else {
                drawCircle(Color.White, w * 0.13f, Offset(cx, cy))
                drawCircle(Ink, w * 0.06f, Offset(cx + w * 0.02f, cy + w * 0.03f))
            }
        }
        if (sleepy) drawOval(Nose, Offset(w / 2 - w * 0.04f + 4, cy + w * 0.16f), Size(w * 0.08f, w * 0.055f))
    }
}

// MARK: Focus

@Composable
fun FocusDashboard(focus: FocusClient, link: MacLink, onClose: () -> Unit) {
    var inspect by remember { mutableStateOf<Pair<FocusSession, String>?>(null) }
    val current = focus.current
    Column(Modifier.fillMaxSize()) {
        TopBar("Focus", if (link.connected) link.macName ?: link.currentMac else "Not connected", onBack = onClose)
        Row(Modifier.fillMaxSize()) {
            Column(Modifier.weight(1f).fillMaxHeight().verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                when {
                    current != null && current.status != FocusStatus.ended -> RunningCard(focus, link, current) { inspect = current to it }
                    else -> {
                        if (current != null) {
                            Text("Lovely bit of focus", style = display(24), color = Ui.Text1)
                            FocusSummary(current, Modifier.background(Ui.Surface, Ui.Card).border(1.dp, Ui.Hairline, Ui.Card).padding(20.dp)) { inspect = current to it }
                        }
                        StartCard(focus, link)
                    }
                }
                if (focus.message.isNotEmpty()) Text(focus.message, style = body(13), color = Ui.Text2)
                DeveloperCard(focus, link)
                Text("While focusing, the computer sends its main display, the task, elapsed and idle time and recent check results to Google Gemini every " +
                    "${if (focus.developerMode) 10 else 30} real seconds. Screenshots aren't saved. Pause, end, lock, sleep or a lost connection stops checks; resuming is always manual.",
                    style = body(12), color = Ui.Text3)
            }
            VerticalDivider(color = Ui.Hairline)
            Column(Modifier.weight(1f).fillMaxHeight()) {
                Row(Modifier.padding(start = 24.dp, end = 24.dp, top = 20.dp, bottom = 8.dp), verticalAlignment = Alignment.Bottom) {
                    Text("History", style = display(20), color = Ui.Text1, modifier = Modifier.weight(1f).semantics { heading() })
                    Text("${focus.history.size}", style = mono(13), color = Ui.Text3)
                }
                if (focus.history.isEmpty()) Text("Your first timeline appears here when a session ends", style = body(14), color = Ui.Text3, modifier = Modifier.padding(horizontal = 24.dp))
                LazyColumn(contentPadding = PaddingValues(start = 24.dp, end = 24.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    items(focus.history, key = { it.id }) { s ->
                        FocusSummary(s, Modifier.background(Ui.Surface, Ui.Card).border(1.dp, Ui.Hairline, Ui.Card).padding(16.dp), compact = true) { inspect = s to it }
                    }
                }
            }
        }
    }
    inspect?.let { (s, c) -> FullScreen({ inspect = null }) { FocusCheckList(s, c) { inspect = null } } }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun StartCard(focus: FocusClient, link: MacLink) {
    var task by remember { mutableStateOf("") }
    var minutes by remember { mutableIntStateOf(30) }
    Column(Modifier.fillMaxWidth().background(Ui.Surface, Ui.Card).border(1.dp, Ui.Hairline, Ui.Card).padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("What are we working on?", style = display(24), color = Ui.Text1)
            Text("Hold Bluey and say it, or type it here", style = body(14), color = Ui.Text2)
        }
        OutlinedTextField(task, { task = it }, Modifier.fillMaxWidth(), placeholder = { Text("Task, like “Write the README”") }, singleLine = true,
            shape = Ui.Control, colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = Ui.Accent, unfocusedBorderColor = Ui.Hairline,
                focusedContainerColor = Ui.Bg, unfocusedContainerColor = Ui.Bg))
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SectionLabel("Duration")
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(15, 25, 30, 45, 60, 90).forEach { m ->
                    FilterChip(minutes == m, { minutes = m }, { Text("$m min", style = mono(13), maxLines = 1, softWrap = false) }, shape = Ui.Control,
                        colors = FilterChipDefaults.filterChipColors(selectedContainerColor = Ui.Accent.copy(alpha = 0.22f), selectedLabelColor = Ui.Text1,
                            labelColor = Ui.Text2, containerColor = Ui.Bg),
                        border = FilterChipDefaults.filterChipBorder(true, minutes == m, borderColor = Ui.Hairline, selectedBorderColor = Ui.Accent))
                }
            }
        }
        PrimaryButton("Start focus", enabled = task.isNotBlank() && link.connected, icon = Icons.Filled.PlayArrow) {
            focus.command("focusStart", task = task.trim(), minutes = minutes.toDouble())
        }
    }
}

@Composable
private fun RunningCard(focus: FocusClient, link: MacLink, s: FocusSession, inspect: (String) -> Unit) {
    val enabled = link.connected && focus.fresh
    val running = s.status == FocusStatus.running
    Column(Modifier.fillMaxWidth().background(Ui.Surface, Ui.Card).border(1.dp, Ui.Hairline, Ui.Card).padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(s.task, style = display(24), color = Ui.Text1, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    StatusDot(if (!focus.fresh) Ui.Warn else if (running) Ui.Good else Ui.Text3)
                    Text(if (focus.fresh) s.detail else "Connection lost. Reconnect before resuming", style = body(13), color = Ui.Text2)
                }
            }
            Text(FocusSession.clock(s.remaining), style = TextStyle(fontFamily = PlexMono, fontSize = 44.sp, fontFeatureSettings = "tnum"), color = Ui.Text1)
        }
        FocusTimeline(s, Modifier.fillMaxWidth().height(32.dp).clip(RoundedCornerShape(6.dp)).clickable { inspect("all") }.semantics { contentDescription = "Inspect focus checks" })
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            SecondaryButton(if (running) "Pause" else "Resume", enabled = enabled, icon = if (running) Icons.Filled.Pause else Icons.Filled.PlayArrow) {
                focus.command(if (running) "focusPause" else "focusResume")
            }
            SecondaryButton("End focus", enabled = enabled, icon = Icons.Filled.Stop) { focus.command("focusEnd") }
        }
    }
}

@Composable
private fun DeveloperCard(focus: FocusClient, link: MacLink) {
    val enabled = link.connected && focus.fresh
    Column(Modifier.fillMaxWidth().background(Ui.Surface, Ui.Card).border(1.dp, Ui.Hairline, Ui.Card).padding(horizontal = 20.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth().heightIn(min = 44.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("Developer mode", style = body(15), color = Ui.Text1)
                Text("4× clock, a check every 10 real seconds, nudges after about 20–30 s. Test sessions are labelled in history.", style = body(12), color = Ui.Text3)
            }
            Spacer(Modifier.width(16.dp))
            Switch(focus.developerMode, { focus.command("focusDeveloperMode", developerMode = it) }, enabled = enabled,
                colors = SwitchDefaults.colors(checkedTrackColor = Ui.Accent, checkedThumbColor = Ui.Text1))
        }
        if (focus.developerMode) SecondaryButton("Test a nudge", enabled = enabled) { focus.command("focusTestNudge") }
    }
}

@Composable
private fun FocusSummary(session: FocusSession, modifier: Modifier = Modifier, compact: Boolean = false, inspect: (String) -> Unit) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(session.task, style = display(if (compact) 17 else 20), color = Ui.Text1, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            Text(FocusSession.clock(session.elapsed), style = mono(13), color = Ui.Text2)
        }
        Text("${dayLabel(session.startedAtMillis)}, ${time(session.startedAtMillis)}" +
            if (session.usedDeveloperMode == true) " · developer test, ${FocusSession.clock(session.realActiveElapsed)} real" else "",
            style = mono(12), color = Ui.Text3)
        FocusTimeline(session, Modifier.fillMaxWidth().height(if (compact) 20.dp else 28.dp).clip(RoundedCornerShape(6.dp))
            .clickable { inspect("all") }.semantics { contentDescription = "Inspect focus checks" })
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            listOf(Triple("On task", Ui.Good, "on_task"), Triple("Off task", Ui.Warn, "off_task"), Triple("Unknown", Ui.Raised, "uncertain")).forEach { (name, color, cat) ->
                Row(Modifier.heightIn(min = 40.dp).clip(Ui.Control).clickable(role = Role.Button) { inspect(cat) }.padding(horizontal = 8.dp)
                    .semantics { contentDescription = "Inspect $name checks" },
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Box(Modifier.size(8.dp).background(color, RoundedCornerShape(2.dp))); Text(name, style = body(12), color = Ui.Text2)
                }
            }
        }
    }
}

@Composable
fun FocusTimeline(session: FocusSession, modifier: Modifier) {
    Canvas(modifier) {
        drawRect(Ui.Raised)
        val total = maxOf(1.0, if (session.status == FocusStatus.ended) session.elapsed else session.duration)
        for (c in session.checks) {
            if (c.activity != FocusActivity.onTask && c.activity != FocusActivity.offTask) continue
            val span = c.sampleDuration ?: 30.0
            val start = maxOf(0.0, c.elapsed - span)
            drawRect(if (c.activity == FocusActivity.onTask) Ui.Good else Ui.Warn,
                Offset((start / total * size.width).toFloat(), 0f), Size((minOf(span, c.elapsed) / total * size.width).toFloat(), size.height))
        }
    }
}

private val FocusActivity.focusName get() = when (this) {
    FocusActivity.onTask -> "On task"; FocusActivity.offTask -> "Off task"; FocusActivity.uncertain -> "Unknown"
    FocusActivity.unavailable -> "Unavailable"; FocusActivity.paused -> "Paused"
}

@Composable
private fun FocusCheckList(session: FocusSession, initial: String, onClose: () -> Unit) {
    var category by remember { mutableStateOf(initial) }
    var detail by remember { mutableStateOf<FocusCheck?>(null) }
    val checks = session.checks.reversed().filter {
        it.activity != FocusActivity.paused && when (category) {
            "all" -> true
            "uncertain" -> it.activity == FocusActivity.uncertain || it.activity == FocusActivity.unavailable
            else -> it.activity.raw == category
        }
    }
    Column(Modifier.fillMaxSize()) {
        TopBar(if (detail == null) "Focus checks" else "Check details", session.task, onBack = { if (detail != null) detail = null else onClose() })
        val d = detail
        if (d != null) { FocusCheckDetail(d); return@Column }
        Column(Modifier.padding(horizontal = 24.dp, vertical = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            SingleChoiceSegmentedButtonRow {
                listOf("all" to "All", "on_task" to "On task", "off_task" to "Off task", "uncertain" to "Unknown").forEachIndexed { i, (k, label) ->
                    SegmentedButton(category == k, { category = k }, SegmentedButtonDefaults.itemShape(i, 4),
                        colors = SegmentedButtonDefaults.colors(activeContainerColor = Ui.Accent.copy(alpha = 0.22f), activeContentColor = Ui.Text1,
                            inactiveContainerColor = Ui.Surface, inactiveContentColor = Ui.Text2, activeBorderColor = Ui.Hairline, inactiveBorderColor = Ui.Hairline)) { Text(label) }
                }
            }
            Text("Each check is a periodic observation. Category probabilities and overall confidence are separate model estimates, not guarantees.",
                style = body(13), color = Ui.Text3)
        }
        if (checks.isEmpty()) Text("No checks in this category yet. Unchecked time has no estimate", style = body(14), color = Ui.Text3, modifier = Modifier.padding(horizontal = 24.dp))
        LazyColumn(contentPadding = PaddingValues(start = 24.dp, end = 24.dp, bottom = 24.dp)) {
            item { Column(Modifier.fillMaxWidth().background(Ui.Surface, Ui.Card).border(1.dp, Ui.Hairline, Ui.Card)) {
                checks.forEachIndexed { i, c ->
                    if (i > 0) HorizontalDivider(color = Ui.Hairline, modifier = Modifier.padding(start = 16.dp))
                    Row(Modifier.fillMaxWidth().clickable { detail = c }.heightIn(min = 56.dp).padding(horizontal = 16.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(FocusSession.clock(c.elapsed), style = mono(13), color = Ui.Text3, modifier = Modifier.width(48.dp))
                        Column(Modifier.weight(1f)) {
                            Text(c.activity.focusName, style = body(15, FontWeight.Medium), color = Ui.Text1)
                            val est = c.estimate(c.activity)
                            Text(when {
                                est != null -> "Probability ${est.percent()} · confidence ${c.confidence.percent()}"
                                c.activity == FocusActivity.unavailable -> "Unavailable or stale · no valid estimate"
                                else -> "Probability not saved · confidence ${c.confidence.percent()}"
                            }, style = body(12), color = Ui.Text3)
                        }
                        if (c.nudged) Icon(Icons.Outlined.ChatBubbleOutline, "Nudged", tint = Ui.Text2, modifier = Modifier.size(16.dp))
                        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = Ui.Text3, modifier = Modifier.size(18.dp))
                    }
                }
            } }
        }
    }
}

@Composable
private fun FocusCheckDetail(c: FocusCheck) {
    @Composable fun row(k: String, v: String) = Row(Modifier.fillMaxWidth().heightIn(min = 40.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(k, style = body(14), color = Ui.Text1, modifier = Modifier.weight(1f)); Text(v, style = mono(13), color = Ui.Text2)
    }
    Column(Modifier.widthIn(max = 640.dp).verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Column(Modifier.background(Ui.Surface, Ui.Card).border(1.dp, Ui.Hairline, Ui.Card).padding(horizontal = 16.dp, vertical = 8.dp)) {
            row("Observation", c.activity.focusName)
            row("Active session time", FocusSession.clock(c.elapsed))
        }
        if (c.activity == FocusActivity.unavailable) {
            Text("This check failed or arrived too late. It has no valid estimate and doesn't count toward a nudge.", style = body(14), color = Ui.Text2)
        } else {
            SectionLabel("Category probabilities")
            Column(Modifier.background(Ui.Surface, Ui.Card).border(1.dp, Ui.Hairline, Ui.Card).padding(horizontal = 16.dp, vertical = 8.dp)) {
                listOf(FocusActivity.onTask, FocusActivity.offTask, FocusActivity.uncertain).forEach { row(it.focusName, c.estimate(it)?.percent() ?: "Not saved") }
            }
            SectionLabel("Decision confidence")
            Column(Modifier.background(Ui.Surface, Ui.Card).border(1.dp, Ui.Hairline, Ui.Card).padding(horizontal = 16.dp, vertical = 8.dp)) {
                row("Overall confidence", c.confidence.percent())
            }
            Text("Confidence is reported separately from the category probabilities.", style = body(13), color = Ui.Text3)
            if (c.probabilities == null) Text("This older check saved only the off-task probability and overall confidence.", style = body(13), color = Ui.Text3)
            if (c.nudged) Text("Bluey gave a gentle nudge after this check", style = body(14), color = Ui.Text2)
        }
    }
}

// MARK: Conversations (iOS BlueyAppView)

@Composable
fun BlueyAppScreen(store: SessionStore, live: LiveVoice, link: MacLink, openFocus: () -> Unit, pairMac: () -> Unit, startListening: () -> Unit, onClose: () -> Unit) {
    var openSession by remember { mutableStateOf<String?>(null) }
    openSession?.let { id -> SessionDetail(store, id) { openSession = null }; return }
    Row(Modifier.fillMaxSize()) {
        Sidebar(live, link, openFocus, pairMac, startListening, onClose)
        VerticalDivider(color = Ui.Hairline)
        ConversationList(store) { openSession = it }
    }
}

@Composable
private fun Sidebar(live: LiveVoice, link: MacLink, openFocus: () -> Unit, pairMac: () -> Unit, startListening: () -> Unit, onClose: () -> Unit) {
    var volume by remember { mutableDoubleStateOf(live.volume) }
    val asleep = live.state == LiveVoice.State.asleep
    Column(Modifier.width(288.dp).fillMaxHeight().background(Ui.Surface).verticalScroll(rememberScrollState()).padding(16.dp)) {
        Row(Modifier.padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            MiniBluey(Modifier.size(44.dp, 40.dp))
            Column {
                Text("Bluey", style = display(22), color = Ui.Text1)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    StatusDot(if (link.connected) Ui.Good else Ui.Text3)
                    Text(if (link.connected) link.macName ?: link.currentMac ?: "Computer" else "Looking for your computer",
                        style = body(12), color = Ui.Text2, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
        Spacer(Modifier.height(20.dp))
        Column(Modifier.fillMaxWidth().background(Ui.Raised, Ui.Card).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                StatusDot(if (asleep) Ui.Text3 else Ui.Accent)
                Text(when (live.state) {
                    LiveVoice.State.asleep -> "Asleep"; LiveVoice.State.waking -> "Waking up"; LiveVoice.State.listening -> "Listening"
                    LiveVoice.State.asking -> "Hearing you"; LiveVoice.State.thinking -> "Thinking"; LiveVoice.State.speaking -> "Replying"
                }, style = body(15, FontWeight.Medium), color = Ui.Text1)
            }
            Text(if (asleep) "Hold his face to ask something; let go and he answers" else "Hold his face to ask. Speech is recognised on your computer",
                style = body(13), color = Ui.Text2)
            if (asleep) PrimaryButton("Start listening", Modifier.fillMaxWidth(), enabled = link.connected, icon = Icons.Filled.Mic) { startListening(); onClose() }
            else SecondaryButton("Stop listening", Modifier.fillMaxWidth(), icon = Icons.Filled.MicOff) { live.sleep() }
        }
        Spacer(Modifier.height(16.dp))
        NavRow(Icons.Filled.CenterFocusStrong, "Focus sessions", openFocus)
        NavRow(Icons.Filled.QrCodeScanner, "Pair computer", pairMac)
        NavRow(Icons.Outlined.Face, "Back to his face", onClose)
        Spacer(Modifier.height(24.dp))
        SectionLabel("Sound", Modifier.padding(horizontal = 4.dp))
        Spacer(Modifier.height(8.dp))
        Box(Modifier.padding(horizontal = 4.dp)) { VolumeControls(live, volume, { volume = it }) }
        Spacer(Modifier.height(16.dp))
        Box(Modifier.padding(horizontal = 4.dp)) { ComputerChooser(link) }
    }
}

@Composable
private fun ConversationList(store: SessionStore, open: (String) -> Unit) {
    val groups = store.sessions.groupBy { dayLabel(it.started) }
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.padding(start = 24.dp, end = 24.dp, top = 20.dp, bottom = 12.dp), verticalAlignment = Alignment.Bottom) {
            Text("Conversations", style = display(24), color = Ui.Text1, modifier = Modifier.weight(1f).semantics { heading() })
            Text(if (store.sessions.size == 1) "1 session" else "${store.sessions.size} sessions", style = mono(13), color = Ui.Text3)
        }
        if (store.sessions.isEmpty()) {
            Column(Modifier.fillMaxSize().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                MiniBluey(Modifier.size(80.dp, 72.dp))
                Spacer(Modifier.height(16.dp))
                Text("No conversations yet", style = display(20), color = Ui.Text1)
                Spacer(Modifier.height(4.dp))
                Text("Hold his face and ask something. Your questions and his replies are kept here", style = body(14), color = Ui.Text2, textAlign = TextAlign.Center)
            }
            return
        }
        LazyColumn(contentPadding = PaddingValues(start = 24.dp, end = 24.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            groups.forEach { (day, sessions) ->
                item(key = "h-$day") { SectionLabel(day, Modifier.padding(top = 12.dp, start = 4.dp)) }
                item(key = "g-$day") {
                    Column(Modifier.fillMaxWidth().clip(Ui.Card).background(Ui.Surface).border(1.dp, Ui.Hairline, Ui.Card)) {
                        sessions.forEachIndexed { i, s ->
                            if (i > 0) HorizontalDivider(color = Ui.Hairline, modifier = Modifier.padding(start = 84.dp))
                            SessionRow(s, s.id == store.currentID) { open(s.id) }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SessionRow(s: BlueySession, live: Boolean, open: () -> Unit) {
    val asked = s.questionCount
    Row(Modifier.fillMaxWidth().clickable(role = Role.Button, onClick = open).heightIn(min = 64.dp).padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        Text(time(s.started), style = mono(14), color = Ui.Text2, modifier = Modifier.width(52.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(s.summary, style = body(15), color = if (s.summary == "Nothing said yet") Ui.Text3 else Ui.Text1, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text("${if (asked == 1) "1 question" else "$asked questions"} · ${durationText(s.duration)}", style = mono(12), color = Ui.Text3)
        }
        if (live) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            StatusDot(Ui.Accent); Text("Live", style = body(13, FontWeight.Medium), color = Ui.Text1)
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = Ui.Text3, modifier = Modifier.size(18.dp))
    }
}

@Composable
private fun SessionDetail(store: SessionStore, id: String, onBack: () -> Unit) {
    val session = store.sessions.firstOrNull { it.id == id } ?: run { LaunchedEffect(Unit) { onBack() }; return }
    val context = LocalContext.current
    val entries = session.displayEntries
    val list = rememberLazyListState()
    var copied by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    LaunchedEffect(entries.size) { if (entries.isNotEmpty()) list.animateScrollToItem(entries.size - 1) }
    LaunchedEffect(copied) { if (copied) { delay(2000); copied = false } }
    BackHandler(onBack = onBack)
    Column(Modifier.fillMaxSize()) {
        TopBar("${dayLabel(session.started)}, ${time(session.started)}",
            "${durationText(session.duration)} · ${if (session.questionCount == 1) "1 question" else "${session.questionCount} questions"}", onBack = onBack) {
            SecondaryButton(if (copied) "Copied" else "Copy prompt for an agent", icon = if (copied) Icons.Filled.Check else Icons.Outlined.ContentCopy) {
                context.getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("Bluey prompt", agentPrompt(session)))
                copied = true
            }
            IconAction(Icons.Filled.Share, "Share transcript") {
                context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, session.exportText), null))
            }
            IconAction(Icons.Outlined.Delete, "Delete conversation") { confirmDelete = true }
        }
        if (entries.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text("Nothing was said in this session", style = body(15), color = Ui.Text3) }
        } else Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
            LazyColumn(Modifier.widthIn(max = 760.dp).fillMaxHeight(), state = list,
                contentPadding = PaddingValues(horizontal = 24.dp, vertical = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                items(entries, key = { it.id }) { EntryView(it) }
            }
        }
    }
    if (confirmDelete) AlertDialog(onDismissRequest = { confirmDelete = false }, containerColor = Ui.Surface,
        title = { Text("Delete this conversation?", style = display(20), color = Ui.Text1) },
        text = { Text("Its transcript is removed from this phone. Notes already written on your computer stay there.", style = body(14), color = Ui.Text2) },
        confirmButton = { TextButton({ confirmDelete = false; store.delete(session.id); onBack() }) { Text("Delete", color = Ui.Danger) } },
        dismissButton = { TextButton({ confirmDelete = false }) { Text("Cancel", color = Ui.Text1) } })
}

private fun agentPrompt(session: BlueySession): String {
    val root = "~/Documents/Bluey Notes"
    val path = session.notesPath?.let { p -> p.indexOf("/Documents/Bluey Notes").takeIf { it >= 0 }?.let { "~" + p.substring(it) } ?: p }
        ?: "$root/ (the folder starting ${SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(session.started))})"
    return "I recorded a conversation with my Bluey app on ${DateFormat.getDateTimeInstance(DateFormat.FULL, DateFormat.SHORT).format(Date(session.started))}. " +
        "The notes are on my computer in $path\n\n- notes.md: the transcript with timestamps, my questions to Bluey, its replies and research reports. Start here.\n" +
        "- session.json: the same data, structured.\n\nAll my sessions are in $root/, one folder per session (see README.md there). Read the notes, then help me with: "
}

@Composable
private fun EntryView(e: TranscriptEntry) {
    when (e.kind) {
        EntryKind.transcript -> Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(e.speaker?.let { "Speaker $it" } ?: "Speaker", style = mono(12), color = Ui.Text3, modifier = Modifier.width(80.dp).padding(top = 2.dp))
            Text(e.text, style = body(15), color = Ui.Text1, modifier = Modifier.weight(1f))
            Text(time(e.time), style = mono(11), color = Ui.Text3, modifier = Modifier.padding(top = 3.dp))
        }
        EntryKind.heard -> Text(e.text, style = body(14), color = Ui.Text2, modifier = Modifier.padding(start = 40.dp))
        EntryKind.asked -> Column(Modifier.fillMaxWidth().padding(start = 96.dp), horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("You asked · ${time(e.time)}", style = mono(11), color = Ui.Text3)
            Text(e.text, style = body(15), color = Ui.Text1, modifier = Modifier
                .background(Ui.Raised, RoundedCornerShape(topStart = 18.dp, topEnd = 6.dp, bottomStart = 18.dp, bottomEnd = 18.dp))
                .padding(horizontal = 16.dp, vertical = 12.dp))
        }
        EntryKind.reply -> Row(Modifier.padding(end = 96.dp), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            MiniBluey(Modifier.size(32.dp, 28.dp))
            Text(e.text, style = display(17), color = Ink, modifier = Modifier
                .background(Color.White, RoundedCornerShape(topStart = 18.dp, topEnd = 18.dp, bottomStart = 6.dp, bottomEnd = 18.dp))
                .padding(horizontal = 16.dp, vertical = 12.dp))
        }
        EntryKind.codex -> Row(Modifier.padding(start = 40.dp, end = 40.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(Icons.Filled.Code, null, tint = Ui.Text3, modifier = Modifier.size(16.dp).padding(top = 2.dp))
            Text(e.text, style = mono(12), color = Ui.Text2, maxLines = 4, overflow = TextOverflow.Ellipsis)
        }
        EntryKind.report -> {
            var open by remember { mutableStateOf(false) }
            val parts = e.text.split("\n\n")
            Column(Modifier.padding(start = 40.dp).fillMaxWidth().background(Ui.Surface, Ui.Card).border(1.dp, Ui.Hairline, Ui.Card).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Outlined.TravelExplore, null, tint = Ui.Text2, modifier = Modifier.size(18.dp))
                    Text(parts.firstOrNull() ?: "Research", style = display(17), color = Ui.Text1, modifier = Modifier.weight(1f))
                }
                Text(parts.drop(1).joinToString("\n\n"), style = body(14), color = Ui.Text2, maxLines = if (open) Int.MAX_VALUE else 3, overflow = TextOverflow.Ellipsis)
                TextButton({ open = !open }, contentPadding = PaddingValues(0.dp)) { Text(if (open) "Show less" else "Read the full report", color = Ui.Text1, style = body(13, FontWeight.Medium)) }
            }
        }
    }
}

