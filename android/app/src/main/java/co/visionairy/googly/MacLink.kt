package co.visionairy.googly

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import co.visionairy.googly.proto.FaceState
import co.visionairy.googly.proto.GooglyService
import co.visionairy.googly.proto.LineConnection
import co.visionairy.googly.proto.Packet
import co.visionairy.googly.proto.PairingRecord
import java.net.InetSocketAddress
import java.net.Socket
import java.util.UUID

/** Finds the paired Mac over DNS-SD (`_googly._tcp`, TXT `bluey-id`) and keeps one authenticated link (iOS MacLink). */
class MacLink(private val context: Context, val pairing: PairingStore) {
    var connected by mutableStateOf(false); private set
    var macName by mutableStateOf<String?>(null); private set
    val macs = mutableStateListOf<String>()
    var currentMac by mutableStateOf<String?>(null); private set
    val preferredMac get() = pairing.preferredMac

    var onCommand: ((String, String?) -> Unit)? = null
    var onFocusState: ((String) -> Unit)? = null
    var onFace: ((FaceState) -> Unit)? = null
    var onConnectedChange: ((Boolean) -> Unit)? = null

    private val main = Handler(Looper.getMainLooper())
    private val nsd = context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private var discovery: NsdManager.DiscoveryListener? = null
    /** Resolved services: Bonjour name → (bluey-id, host, port). */
    private val resolved = mutableMapOf<String, Triple<String?, java.net.InetAddress, Int>>()
    private val resolveQueue = ArrayDeque<NsdServiceInfo>()
    private var resolving = false
    private var link: LineConnection? = null
    private var connecting = false
    private val waiting = mutableMapOf<String, (Packet?) -> Unit>()
    private val retry = Runnable { if (discovery == null) start() else connectIfNeeded() }

    fun start() {
        if (discovery != null) return
        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) {}
            override fun onDiscoveryStopped(serviceType: String) {}
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) = main.post { discovery = null; scheduleRetry() }.let {}
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
            override fun onServiceFound(info: NsdServiceInfo) = main.post {
                Log.d(TAG, "found ${info.serviceName}")
                if (info.serviceName !in macs) { macs.add(info.serviceName); macs.sort() }
                resolveQueue.addLast(info); resolveNext()
            }.let {}
            override fun onServiceLost(info: NsdServiceInfo) = main.post {
                macs.remove(info.serviceName); resolved.remove(info.serviceName)
            }.let {}
        }
        discovery = listener
        nsd.discoverServices(GooglyService.TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
    }

    fun stop() {
        main.removeCallbacks(retry)
        discovery?.let { runCatching { nsd.stopServiceDiscovery(it) } }
        discovery = null
        resolveQueue.clear(); resolved.clear(); macs.clear()
        link?.cancel(); link = null
        updateConnected(false)
        failWaiting()
    }

    private fun scheduleRetry() {
        main.removeCallbacks(retry)
        main.postDelayed(retry, 1500)
    }

    // shortcut: NsdManager.resolveService allows one resolve at a time before API 34; queue them.
    @Suppress("DEPRECATION")
    private fun resolveNext() {
        if (resolving) return
        val info = resolveQueue.removeFirstOrNull() ?: return
        resolving = true
        nsd.resolveService(info, object : NsdManager.ResolveListener {
            override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) = main.post {
                Log.d(TAG, "resolve failed ${serviceInfo.serviceName} $errorCode")
                resolving = false; resolveNext()
            }.let {}
            override fun onServiceResolved(s: NsdServiceInfo) = main.post {
                resolving = false
                val id = s.attributes["bluey-id"]?.let { String(it, Charsets.UTF_8) }
                val host = if (Build.VERSION.SDK_INT >= 34) s.hostAddresses.firstOrNull() else s.host
                Log.d(TAG, "resolved ${s.serviceName} $host:${s.port} id=$id")
                if (host != null) resolved[s.serviceName] = Triple(id, host, s.port)
                connectIfNeeded()
                resolveNext()
            }.let {}
        })
    }

    fun choose(name: String) {
        pairing.preferredMac = name
        if (currentMac != name) link?.cancel()
        connectIfNeeded()
    }

    private fun connectIfNeeded() {
        val record = pairing.load() ?: return
        val secret = record.key ?: return
        if (link != null || connecting) return
        val (name, target) = resolved.entries.firstOrNull { it.value.first == record.identifier }?.toPair() ?: return
        currentMac = name
        connecting = true
        Thread {
            val socket = runCatching { Socket().apply { connect(InetSocketAddress(target.second, target.third), 5000) } }
            main.post {
                connecting = false
                val s = socket.getOrNull()
                Log.d(TAG, "connect $name ${if (s == null) "failed" else "ok"}")
                if (s == null) { resolved.remove(name); scheduleRetry(); return@post }
                open(s, secret)
            }
        }.start()
    }

    private fun open(socket: Socket, secret: ByteArray) {
        val link = LineConnection(socket, secret, server = false, callbacks = { main.post(it) })
        this.link = link
        link.onClosed = {
            Log.d(TAG, "link closed: ${link.closeReason}")
            if (link === this.link) {
                this.link = null
                macName = null
                updateConnected(false)
                failWaiting()
                scheduleRetry()
            }
        }
        link.onAuthenticated = {
            if (link === this.link) {
                updateConnected(true)
                link.send(Packet(hello = deviceName))
                link.send(Packet(command = "focusSync"))
            }
        }
        link.onPacket = { packet ->
            packet.hello?.let { macName = it }
            packet.face?.let { onFace?.invoke(it) }
            val command = packet.command
            if (command != null) {
                if (command == "focusState" && packet.text != null) onFocusState?.invoke(packet.text)
                else {
                    val done = packet.callID?.let { waiting.remove(it) }
                    if (done != null) done(packet) else onCommand?.invoke(command, packet.text)
                }
            }
        }
        link.start()
    }

    private fun updateConnected(value: Boolean) {
        if (connected == value) return
        Log.d(TAG, "authenticated=$value")
        connected = value
        onConnectedChange?.invoke(value)
    }

    private fun failWaiting() {
        val pending = waiting.values.toList(); waiting.clear(); pending.forEach { it(null) }
    }

    fun pair(record: PairingRecord): Boolean {
        if (!pairing.save(record)) return false
        stop(); start()
        return true
    }

    fun send(packet: Packet) { link?.send(packet) }

    /** Sends a request; [done] gets the reply or null after 12 s / disconnect. Main thread. */
    fun request(packet: Packet, done: (Packet?) -> Unit) {
        val link = link
        if (link == null || !connected) { done(null); return }
        val id = UUID.randomUUID().toString().uppercase()
        waiting[id] = done
        main.postDelayed({ waiting.remove(id)?.invoke(null) }, 12_000)
        link.send(packet.copy(callID = id))
    }

    private val deviceName: String get() =
        Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME) ?: Build.MODEL

    private companion object { const val TAG = "BlueyLink" } // never log pairing secrets here
}
