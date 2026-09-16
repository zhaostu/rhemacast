package com.rhemacast

import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.webrtc.AudioTrack
import org.webrtc.MediaConstraints
import org.webrtc.MediaStreamTrack
import org.webrtc.PeerConnection
import org.webrtc.PeerConnectionFactory
import org.webrtc.RTCStatsReport
import org.webrtc.RtpTransceiver
import org.webrtc.SdpObserver
import org.webrtc.SessionDescription
import org.webrtc.audio.JavaAudioDeviceModule
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Audio-only WebRTC receiver using WHEP against rhemacastd.
 *
 * Flow: create recvonly PeerConnection -> createOffer -> wait for ICE
 * gather -> POST SDP to http://<ip>:8080/whep -> setRemote(answer).
 *
 * No local AudioSource is created and no RECORD_AUDIO is needed:
 * direction is RECV_ONLY, remote AudioTrack is playback-only.
 */
class WebRTCClient(
    private val context: Context,
    private val listener: Listener,
) {
    interface Listener {
        fun onStatus(s: String)
        fun onStats(s: String)
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var factory: PeerConnectionFactory? = null
    private var peerConnection: PeerConnection? = null
    private var audioDeviceModule: JavaAudioDeviceModule? = null
    private var statsJob: Job? = null
    private var iceGatheringDone: (() -> Unit)? = null

    private val http = OkHttpClient.Builder()
        .connectTimeout(8, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .build()

    @Volatile var connected = false
        private set

    suspend fun connect(hostIp: String) {
        val ip = hostIp.trim()
        require(ip.isNotEmpty()) { "Empty IP" }
        disconnectInternal(silent = true)
        try {
            listener.onStatus("Connecting to $ip …")
            ensureFactory()
            val pc = createPeerConnection()
            peerConnection = pc

            val offer = createOffer(pc)
            setLocal(pc, offer)
            waitForIceGathering(pc, timeoutMs = 2500)

            // Re-read local description after gathering (contains ICE candidates).
            val localSdp = pc.localDescription?.description
                ?: throw IllegalStateException("No local SDP after offer")
            val answerSdp = postWhep("http://$ip:8080/whep", localSdp)
            setRemote(pc, SessionDescription(SessionDescription.Type.ANSWER, answerSdp))

            // Voice-call routing (headphones by default via
            // AudioRouter; loudspeaker only on explicit user choice).
            // WebRTC ADM does the actual rendering; we own the route.
            val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            AudioRouter.apply(am)
            watchRoutes()
            connected = true
            listener.onStatus("Playing from $ip")
            startStatsLoop()
        } catch (e: Exception) {
            disconnectInternal(silent = true)
            // Offline-friendly: never crash, surface a human-readable reason.
            // NB: our own "WHEP HTTP <code>" errors carry the code — show them
            // as-is instead of the generic unreachable hint.
            val hint = when {
                e.message?.startsWith("WHEP HTTP") == true -> e.message ?: e.toString()
                e is java.net.UnknownHostException ||
                    e is java.net.ConnectException ||
                    e is java.net.SocketTimeoutException ||
                    e is java.io.IOException
                -> "Unreachable. Check same LAN, IP, and rhemacastd :8080."
                else -> e.message ?: e.toString()
            }
            listener.onStatus("Error: $hint")
            listener.onStats("")
        }
    }

    fun disconnect() {
        scope.launch { disconnectInternal() }
    }

    fun release() {
        scope.launch {
            disconnectInternal()
            try {
                factory?.dispose()
            } catch (_: Exception) {
            }
            factory = null
            try {
                audioDeviceModule?.release()
            } catch (_: Exception) {
            }
            audioDeviceModule = null
            http.dispatcher.executorService.shutdown()
            http.connectionPool.evictAll()
        }
    }

    // ---- internals ----

    private fun ensureFactory() {
        if (factory != null) return
        val initOptions = PeerConnectionFactory.InitializationOptions.builder(context)
            .createInitializationOptions()
        PeerConnectionFactory.initialize(initOptions)
        audioDeviceModule = JavaAudioDeviceModule.builder(context).createAudioDeviceModule()
        factory = PeerConnectionFactory.builder()
            .setOptions(PeerConnectionFactory.Options())
            .setAudioDeviceModule(audioDeviceModule)
            .createPeerConnectionFactory()
    }

    private fun createPeerConnection(): PeerConnection {
        val f = factory ?: throw IllegalStateException("Factory not initialised")
        val config = PeerConnection.RTCConfiguration(emptyList()).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
        }
        val observer = object : PeerConnection.Observer {
            override fun onIceGatheringChange(state: PeerConnection.IceGatheringState) {
                if (state == PeerConnection.IceGatheringState.COMPLETE) iceGatheringDone?.invoke()
            }
            override fun onAddTrack(receiver: org.webrtc.RtpReceiver, streams: Array<out org.webrtc.MediaStream>) {
                (receiver.track() as? AudioTrack)?.setEnabled(true)
            }
            override fun onIceCandidate(c: org.webrtc.IceCandidate) = Unit
            override fun onIceCandidatesRemoved(c: Array<out org.webrtc.IceCandidate>) = Unit
            override fun onIceConnectionChange(s: PeerConnection.IceConnectionState) {
                if (s == PeerConnection.IceConnectionState.FAILED ||
                    s == PeerConnection.IceConnectionState.DISCONNECTED
                ) listener.onStatus("Connection ${s.name.lowercase()}")
            }
            override fun onSignalingChange(s: PeerConnection.SignalingState) = Unit
            override fun onIceConnectionReceivingChange(b: Boolean) = Unit
            override fun onRemoveTrack(r: org.webrtc.RtpReceiver) = Unit
            override fun onDataChannel(d: org.webrtc.DataChannel) = Unit
            override fun onRenegotiationNeeded() = Unit
            override fun onAddStream(s: org.webrtc.MediaStream) = Unit
            override fun onRemoveStream(s: org.webrtc.MediaStream) = Unit
        }
        val pc = f.createPeerConnection(config, observer)
            ?: throw IllegalStateException("createPeerConnection failed")
        // Audio-only recvonly: no local AudioSource/Track (no mic capture).
        pc.addTransceiver(
            MediaStreamTrack.MediaType.MEDIA_TYPE_AUDIO,
            RtpTransceiver.RtpTransceiverInit(RtpTransceiver.RtpTransceiverDirection.RECV_ONLY),
        )
        return pc
    }

    private suspend fun createOffer(pc: PeerConnection): SessionDescription =
        suspendCancellableCoroutine { cont ->
            val constraints = MediaConstraints().apply {
                mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveAudio", "true"))
                mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveVideo", "false"))
            }
            pc.createOffer(object : SdpObserver {
                override fun onCreateSuccess(sdp: SessionDescription) {
                    if (cont.isActive) cont.resume(sdp)
                }
                override fun onCreateFailure(err: String) {
                    if (cont.isActive) cont.resumeWithException(IllegalStateException(err))
                }
                override fun onSetSuccess() = Unit
                override fun onSetFailure(err: String) = Unit
            }, constraints)
        }

    private suspend fun setLocal(pc: PeerConnection, sdp: SessionDescription) =
        suspendCancellableCoroutine<Unit> { cont ->
            pc.setLocalDescription(object : SdpObserver {
                override fun onSetSuccess() {
                    if (cont.isActive) cont.resume(Unit)
                }
                override fun onSetFailure(err: String) {
                    if (cont.isActive) cont.resumeWithException(IllegalStateException(err))
                }
                override fun onCreateSuccess(s: SessionDescription) = Unit
                override fun onCreateFailure(err: String) = Unit
            }, sdp)
        }

    private suspend fun setRemote(pc: PeerConnection, sdp: SessionDescription) =
        suspendCancellableCoroutine<Unit> { cont ->
            pc.setRemoteDescription(object : SdpObserver {
                override fun onSetSuccess() {
                    if (cont.isActive) cont.resume(Unit)
                }
                override fun onSetFailure(err: String) {
                    if (cont.isActive) cont.resumeWithException(IllegalStateException(err))
                }
                override fun onCreateSuccess(s: SessionDescription) = Unit
                override fun onCreateFailure(err: String) = Unit
            }, sdp)
        }

    private suspend fun waitForIceGathering(pc: PeerConnection, timeoutMs: Long) {
        if (pc.iceGatheringState() == PeerConnection.IceGatheringState.COMPLETE) return
        // rhemacastd WHEP works with a plain non-trickle offer, so a bounded wait
        // is enough: resume early on COMPLETE, otherwise proceed after timeout.
        withTimeoutOrNull(timeoutMs) {
            suspendCancellableCoroutine<Unit> { cont ->
                iceGatheringDone = { if (cont.isActive) cont.resume(Unit) }
                cont.invokeOnCancellation { iceGatheringDone = null }
            }
        }
        iceGatheringDone = null
    }

    private suspend fun postWhep(url: String, offerSdp: String): String {
        val body = offerSdp.toRequestBody("application/sdp".toMediaType())
        val req = Request.Builder().url(url).post(body)
            .header("Content-Type", "application/sdp")
            .build()
        // Network on Default dispatcher is fine (OkHttp is blocking); called from scope.
        val res = http.newCall(req).execute()
        res.use {
            if (!it.isSuccessful) throw java.io.IOException("WHEP HTTP ${it.code}")
            // Server returns pristine CRLF-terminated SDP; pass it through
            // untouched (trimming would strip the required trailing CRLF).
            val sdp = it.body?.string() ?: ""
            if (sdp.isBlank()) throw java.io.IOException("Empty WHEP answer")
            return sdp
        }
    }

    private fun startStatsLoop() {
        statsJob?.cancel()
        statsJob = scope.launch {
            while (true) {
                delay(2000)
                val pc = peerConnection ?: break
                pc.getStats { report: RTCStatsReport ->
                    listener.onStats(formatInboundAudio(report))
                }
            }
        }
    }

    private fun formatInboundAudio(report: RTCStatsReport): String {
        for (stats in report.statsMap.values) {
            if (stats.type == "inbound-rtp") {
                val m = stats.members
                val kind = m["kind"] as? String ?: ""
                if (kind.isNotEmpty() && kind != "audio") continue
                val bytes = (m["bytesReceived"] as? Number)?.toLong()
                val lost = (m["packetsLost"] as? Number)?.toLong()
                val jitter = (m["jitter"] as? Number)?.toDouble()
                val parts = mutableListOf<String>()
                bytes?.let { parts += "rx ${(it / 1024)} KB" }
                lost?.let { parts += "lost $it" }
                jitter?.let { parts += "jitter ${"%.1f".format(it * 1000)} ms" }
                if (parts.isNotEmpty()) return parts.joinToString(" · ")
            }
        }
        return "receiving audio…"
    }

    private var deviceCallback: AudioDeviceCallback? = null

    // Re-apply routing when outputs change (e.g. BT headset connected
    // mid-session), so it takes over without toggling output/reconnecting.
    private fun watchRoutes() {
        unwatchRoutes()
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val cb = object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(added: Array<out AudioDeviceInfo>) {
                reapplyRoute()
            }
            override fun onAudioDevicesRemoved(removed: Array<out AudioDeviceInfo>) {
                reapplyRoute()
            }
        }
        deviceCallback = cb
        try {
            am.registerAudioDeviceCallback(cb, null)
        } catch (_: Exception) {
        }
    }

    private fun reapplyRoute() {
        try {
            AudioRouter.apply(context.getSystemService(Context.AUDIO_SERVICE) as AudioManager)
        } catch (_: Exception) {
        }
    }

    private fun unwatchRoutes() {
        val cb = deviceCallback ?: return
        deviceCallback = null
        try {
            val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            am.unregisterAudioDeviceCallback(cb)
        } catch (_: Exception) {
        }
    }

    private suspend fun disconnectInternal(silent: Boolean = false) {
        connected = false
        statsJob?.cancel()
        statsJob = null
        unwatchRoutes()
        // Null-first so concurrent disconnects can't double-teardown.
        // NB: close() only — pc.dispose() crashes this WebRTC build
        // ("RtpSender has been disposed", incl. an uncatchable native
        // double-free in RtpTransceiver.dispose).
        val pc = peerConnection
        peerConnection = null
        try {
            pc?.close()
        } catch (_: Exception) {
        }
        try {
            AudioRouter.restore(context.getSystemService(Context.AUDIO_SERVICE) as AudioManager)
        } catch (_: Exception) {
        }
        if (!silent) {
            listener.onStatus("Disconnected")
            listener.onStats("")
        }
    }
}
