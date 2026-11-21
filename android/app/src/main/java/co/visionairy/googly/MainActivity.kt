package co.visionairy.googly

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.SystemClock
import android.view.HapticFeedbackConstants
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import co.visionairy.googly.proto.Mood
import co.visionairy.googly.proto.Packet
import co.visionairy.googly.proto.PairingRecord
import co.visionairy.googly.ui.*
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private val link by lazy { MacLink(applicationContext, PairingStore(applicationContext)) }
    private val live by lazy { LiveVoice(applicationContext) }
    private val store by lazy { SessionStore(applicationContext) }
    private val focus by lazy { FocusClient(applicationContext) }
    private val animator = FaceAnimator()

    private var pairError by mutableStateOf("")
    private val scan = registerForActivityResult(ScanContract()) { result ->
        val text = result.contents ?: return@registerForActivityResult
        val record = PairingRecord.parse(text)
        pairError = when {
            record == null -> "That isn't a Bluey pairing code."
            !link.pair(record) -> "Couldn't save pairing securely. Try again."
            else -> ""
        }
    }
    private val micPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) live.wake() else live.micDenied()
    }

    private fun scanPairing() = scan.launch(ScanOptions().setDesiredBarcodeFormats(ScanOptions.QR_CODE).setBeepEnabled(false)
        .setOrientationLocked(false).setPrompt("On your computer, open Bluey's menu and choose Pair phone (QR)"))

    private fun hasMic() = checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    /** Wake needs the microphone; ask once, then wake. */
    private fun wakeWithMic() = if (hasMic()) live.wake() else micPermission.launch(Manifest.permission.RECORD_AUDIO)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowInsetsControllerCompat(window, window.decorView).apply {
            hide(WindowInsetsCompat.Type.systemBars())
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }
        wire()
        debugPair(intent)
        setContent { MaterialTheme(colorScheme = darkColorScheme(primary = Berry2, background = Ui.Bg, surface = Ui.Surface, onSurface = Ui.Text1, onBackground = Ui.Text1)) { Root() } }
    }

    override fun onNewIntent(intent: android.content.Intent) { super.onNewIntent(intent); debugPair(intent) }

    /** Debug builds only: `adb shell am start -n co.visionairy.googly.phone/co.visionairy.googly.MainActivity --es pair 'bluey-pair:…'`. */
    private fun debugPair(intent: android.content.Intent?) {
        if (!BuildConfig.DEBUG) return
        val text = intent?.getStringExtra("pair") ?: return
        intent.removeExtra("pair")
        pairError = PairingRecord.parse(text)?.let { if (link.pair(it)) "" else "Couldn't save pairing securely." } ?: "That isn't a Bluey pairing code."
    }

    override fun onStart() { super.onStart(); link.start() }

    override fun onStop() {
        // Backgrounding pauses monitoring and voice, like iOS scene phase changes.
        focus.command("focusPause")
        live.sleep()
        link.stop()
        super.onStop()
    }

    private fun wire() {
        focus.attach(link)
        link.onFocusState = { focus.receive(it) }
        link.onFace = { animator.receive(it, SystemClock.uptimeMillis() / 1000.0) }
        animator.localTalk = { live.level }
        link.onConnectedChange = { connected ->
            focus.connectionChanged(connected)
            if (!connected) live.sleep() else store.resyncRecent()
        }
        live.requestToken = { done -> link.request(Packet(command = "realtimeToken")) { done(it?.text) } }
        live.runTool = { name, args, done ->
            link.request(Packet(command = "tool", tool = name, text = args)) { done(it?.text ?: "The computer didn't answer.", it?.image) }
        }
        live.onSessionStart = { store.start() } // Focus voice is ephemeral; meeting audio isn't recorded (as on iOS).
        live.resumeContext = { store.recentText() }
        live.transcribeLocal = { pcm, done ->
            link.request(Packet(command = "hear", audio = java.util.Base64.getEncoder().encodeToString(pcm))) { done(it?.text) }
        }
        store.onSync = { SessionStore.sync(it, store, link) }
        live.onSessionEnd = { store.end() }
        live.onUserTurn = { item, asked -> store.placeholder(item, asked) }
        live.onUserWords = { item, text, asked -> store.heard(item, text, asked) }
        live.onReply = { store.reply(it) }
        live.onReport = { store.report(it) }
        live.onCaption = { text, finished -> link.send(Packet(command = if (finished) "captionDone" else "caption", text = text)) }
        live.onStateChange = { state ->
            when (state) {
                LiveVoice.State.asleep -> { animator.awake = false; animator.localMood = null; link.send(Packet(command = "asleep")) }
                LiveVoice.State.waking -> { animator.awake = true; animator.localMood = Mood.happy }
                LiveVoice.State.listening -> { animator.awake = true; animator.localMood = null; link.send(Packet(command = "awake")) }
                LiveVoice.State.asking -> { animator.awake = true; animator.localMood = Mood.listening; link.send(Packet(command = "awake")) }
                LiveVoice.State.thinking -> animator.localMood = Mood.thinking
                LiveVoice.State.speaking -> animator.localMood = Mood.talking
            }
        }
        live.onCodexNote = { store.codex(it) }
        link.onCommand = { command, text ->
            when (command) {
                "wake" -> wakeWithMic()
                "sleep" -> live.sleep()
                "codexNote" -> live.codexNote(text ?: "")
                "codexChirp" -> live.chirpAlone()
                "focusChirp" -> { focus.receivedNudge(text ?: "Are you sure you're on task right now?"); live.focusChirp() }
            }
        }
    }

    @Composable
    private fun Root() {
        var showFocus by remember { mutableStateOf(false) }
        var showApp by remember { mutableStateOf(false) }
        var showPairing by remember { mutableStateOf(true) }
        LaunchedEffect(Unit) { focus.onFinished = { showFocus = true; live.sleep() } }
        LaunchedEffect(link.connected) { if (link.connected) showPairing = false }
        val view = LocalView.current
        val scope = rememberCoroutineScope()

        Box(Modifier.fillMaxSize().background(Color.Black)) {
            FaceCanvas(animator, Modifier.fillMaxSize().pointerInput(Unit) {
                var holding = false
                detectTapGestures(
                    onDoubleTap = { if (live.state == LiveVoice.State.asleep) wakeWithMic() else live.sleep() },
                    onPress = {
                        // A quick tap isn't a hold: wait 0.3 s before listening.
                        var job: Job? = scope.launch {
                            delay(300)
                            holding = true
                            view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                            if (live.state == LiveVoice.State.asleep && !hasMic()) micPermission.launch(Manifest.permission.RECORD_AUDIO)
                            else live.beginAsk()
                        }
                        tryAwaitRelease()
                        job?.cancel(); job = null
                        if (holding) { holding = false; view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY); live.endAsk() }
                    },
                )
            })
            ModeIndicator(live.state)
            CaptionBubble(live)
            FocusFaceHUD(focus, link, live, open = { showFocus = true }, pair = ::scanPairing)
            SoundButton(link, live)
            Box(Modifier.align(Alignment.TopEnd).padding(top = 10.dp, end = 62.dp)) {
                androidx.compose.material3.IconButton({ showApp = true }) {
                    androidx.compose.material3.Icon(Icons.Filled.GridView, "Open Bluey", tint = Color.White.copy(alpha = 0.35f))
                }
            }
            if (showPairing && !link.connected) PairingOverlay { showPairing = false; scanPairing() }
            if (pairError.isNotEmpty()) androidx.compose.material3.Text(pairError, Modifier.align(Alignment.BottomCenter).padding(24.dp), color = Color(0xFFFFA500))
        }
        if (showApp) FullScreen({ showApp = false }) {
            BlueyAppScreen(store, live, link, openFocus = { showApp = false; showFocus = true }, pairMac = { showApp = false; scanPairing() },
                startListening = ::wakeWithMic, onClose = { showApp = false })
        }
        if (showFocus) FullScreen({ showFocus = false }) { FocusDashboard(focus, link) { showFocus = false } }
    }
}
