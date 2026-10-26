package za.co.n2it.phone

import android.content.Context
import android.os.Handler
import android.os.Looper
import org.webrtc.AudioSource
import org.webrtc.AudioTrack
import org.webrtc.DataChannel
import org.webrtc.IceCandidate
import org.webrtc.MediaConstraints
import org.webrtc.MediaStream
import org.webrtc.PeerConnection
import org.webrtc.PeerConnectionFactory
import org.webrtc.RtpReceiver
import org.webrtc.RtpSender
import org.webrtc.RtpTransceiver
import org.webrtc.SdpObserver
import org.webrtc.SessionDescription
import org.webrtc.audio.JavaAudioDeviceModule

/*
 * Call audio over WebRTC (Google's library, BSD licence): Opus/G.711, DTLS-SRTP encryption, echo cancellation and noise
 * suppression built in. One PeerConnection per call; the SDP goes to and from the PBX inside SIP (SipStack.kt), with
 * all ICE candidates included (the PBX does not do trickle ICE), like the desktop app.
 */
object Rtc {
    private var factory: PeerConnectionFactory? = null
    private var adm: JavaAudioDeviceModule? = null
    private var initialised = false
    private var builtWithHwAec = false
    /** Calls using the factory: a changed setting only rebuilds it when none is up. */
    var inUse = 0

    /** "Use the phone's own echo canceller" (Settings). Off = WebRTC's software canceller (as Google Meet); on = the
     *  maker's built-in one. 0.3.0 test 2026-10-22: on the HONOR the built-in one let a mobile caller hear herself. */
    fun hwAec(context: Context) = context.getSharedPreferences("n2it_echo", Context.MODE_PRIVATE).getBoolean("hw_aec", false)

    fun factory(context: Context): PeerConnectionFactory {
        val hw = hwAec(context)
        factory?.let { if (hw == builtWithHwAec || inUse > 0) return it }
        release()
        if (!initialised) {
            PeerConnectionFactory.initialize(PeerConnectionFactory.InitializationOptions.builder(context.applicationContext)
                .createInitializationOptions())
            initialised = true
        }
        val a = JavaAudioDeviceModule.builder(context.applicationContext)
            .setUseHardwareAcousticEchoCanceler(hw)
            .setUseHardwareNoiseSuppressor(hw)
            .createAudioDeviceModule()
        adm = a; builtWithHwAec = hw
        return PeerConnectionFactory.builder().setAudioDeviceModule(a).createPeerConnectionFactory().also { factory = it }
    }

    /** Only between calls: the next call builds a new one with the current settings. */
    private fun release() {
        factory?.dispose(); factory = null
        adm?.release(); adm = null
    }
}

/**
 * The audio of one call. [onEnded] is called when the audio connection fails for good (network gone), so the call can
 * be hung up instead of staying silent.
 */
class CallMedia(context: Context, noiseFilter: Boolean, private val onFailed: () -> Unit) {
    private val main = Handler(Looper.getMainLooper())
    private val factory = Rtc.factory(context).also { Rtc.inUse++ }
    private val source: AudioSource
    private val track: AudioTrack
    private val pc: PeerConnection
    private val sender: RtpSender
    /** Our audio's transceiver; for a call the PBX offered it only exists once its offer is applied. */
    private val transceiver: RtpTransceiver? get() = pc.transceivers.firstOrNull { it.sender.id() == sender.id() }
    private var candidates = 0
    private var closed = false
    private var gathered: (() -> Unit)? = null
    private val quiet = Runnable { gatherDone() }
    private val cap = Runnable { gatherDone() }

    private val observer = object : PeerConnection.Observer {
        override fun onIceCandidate(candidate: IceCandidate) {
            // Go once candidates have been quiet for 0.5 s: a dead interface or slow STUN server would otherwise hold the
            // call up for ~40 s (1 s, as the desktop, added a second to every call)
            main.post { candidates++; if (gathered != null) { main.removeCallbacks(quiet); main.postDelayed(quiet, 500) } }
        }
        override fun onIceGatheringChange(state: PeerConnection.IceGatheringState) {
            // "Complete" with no address at all is not done (0.3.0 test: an answer with none, the PBX hung up): wait for the 4 s cap
            if (state == PeerConnection.IceGatheringState.COMPLETE) main.post { if (candidates > 0) gatherDone() }
        }
        override fun onConnectionChange(state: PeerConnection.PeerConnectionState) {
            if (state == PeerConnection.PeerConnectionState.FAILED) main.post { if (!closed) onFailed() }
        }
        override fun onSignalingChange(state: PeerConnection.SignalingState) {}
        override fun onIceConnectionChange(state: PeerConnection.IceConnectionState) {}
        override fun onIceConnectionReceivingChange(receiving: Boolean) {}
        override fun onIceCandidatesRemoved(candidates: Array<out IceCandidate>) {}
        override fun onAddStream(stream: MediaStream) {}
        override fun onRemoveStream(stream: MediaStream) {}
        override fun onDataChannel(channel: DataChannel) {}
        override fun onRenegotiationNeeded() {}
        override fun onAddTrack(receiver: RtpReceiver, streams: Array<out MediaStream>) {}
    }

    init {
        val c = MediaConstraints().apply {
            mandatory += MediaConstraints.KeyValuePair("googEchoCancellation", "true")
            mandatory += MediaConstraints.KeyValuePair("googAutoGainControl", "true")
            mandatory += MediaConstraints.KeyValuePair("googNoiseSuppression", noiseFilter.toString())
            mandatory += MediaConstraints.KeyValuePair("googHighpassFilter", "true")
        }
        source = factory.createAudioSource(c)
        track = factory.createAudioTrack("n2it-mic", source)
        val cfg = PeerConnection.RTCConfiguration(listOf(
            PeerConnection.IceServer.builder("stun:stun.l.google.com:19302").createIceServer())).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
            // Balanced, as browsers: FreeSWITCH offers no BUNDLE group, which max-bundle refuses ("no BUNDLE group")
            bundlePolicy = PeerConnection.BundlePolicy.BALANCED
            rtcpMuxPolicy = PeerConnection.RtcpMuxPolicy.REQUIRE
            tcpCandidatePolicy = PeerConnection.TcpCandidatePolicy.DISABLED
            continualGatheringPolicy = PeerConnection.ContinualGatheringPolicy.GATHER_ONCE
            keyType = PeerConnection.KeyType.ECDSA
        }
        pc = factory.createPeerConnection(cfg, observer) ?: error("WebRTC could not start")
        // addTrack, not addTransceiver: only a track added this way is reused for the PBX's offer (JSEP); a transceiver
        // made by addTransceiver is left aside and the call answered "recvonly" with no microphone (0.3.0 test, 12:19)
        sender = pc.addTrack(track, listOf("n2it"))
    }

    private fun gatherDone() {
        main.removeCallbacks(quiet); main.removeCallbacks(cap)
        val g = gathered ?: return
        gathered = null
        if (!closed) g()
    }

    /** Our SDP once the candidates are in (or after 4 s at most). */
    private fun afterGathering(done: (String?) -> Unit) {
        val result = {
            val sdp = pc.localDescription?.description
            if (sdp != null && !sdp.contains("a=candidate")) { lastError = "no network address for the audio (ICE gathered nothing)"; done(null) }
            else done(sdp)
        }
        if (candidates > 0 && pc.iceGatheringState() == PeerConnection.IceGatheringState.COMPLETE) { result(); return }
        gathered = result
        main.postDelayed(cap, 4000)
    }

    private fun setLocal(desc: SessionDescription, done: (String?) -> Unit) {
        pc.setLocalDescription(object : Sdp() {
            override fun onSetSuccess() { main.post { if (closed) done(null) else afterGathering(done) } }
            override fun onSetFailure(error: String?) { main.post { lastError = "local: $error"; done(null) } }
        }, desc)
    }

    /** New call or re-INVITE from us: an offer with all our candidates; null if WebRTC could not make one. */
    fun offer(done: (String?) -> Unit) {
        pc.createOffer(object : Sdp() {
            override fun onCreateSuccess(desc: SessionDescription) { main.post { if (closed) done(null) else setLocal(desc, done) } }
            override fun onCreateFailure(error: String?) { main.post { lastError = "offer: $error"; done(null) } }
        }, MediaConstraints())
    }

    /** The PBX's offer (incoming call, or its re-INVITE): our answer, or null if the offer cannot be used. */
    fun answer(remote: String, done: (String?) -> Unit) {
        pc.setRemoteDescription(object : Sdp() {
            override fun onSetSuccess() {
                main.post {
                    if (closed) { done(null); return@post }
                    pc.createAnswer(object : Sdp() {
                        override fun onCreateSuccess(desc: SessionDescription) { main.post { if (closed) done(null) else setLocal(desc, done) } }
                        override fun onCreateFailure(error: String?) { main.post { lastError = "answer: $error"; done(null) } }
                    }, MediaConstraints())
                }
            }
            override fun onSetFailure(error: String?) { main.post { lastError = "remote offer: $error"; done(null) } }
        }, SessionDescription(SessionDescription.Type.OFFER, withMids(remote)))
    }

    /** WebRTC's own words for the last failure, for the tester to send to N2IT. */
    var lastError: String? = null; private set

    /** FreeSWITCH's SDP has no a=mid (old-style WebRTC); newer WebRTC wants one per m= line: 0, 1, … in order. */
    private fun withMids(sdp: String): String {
        if (sdp.contains("a=mid:")) return sdp
        var i = 0
        return sdp.split("\r\n").joinToString("\r\n") { line -> if (line.startsWith("m=")) "$line\r\na=mid:${i++}" else line }
    }

    private var lastRemote: String? = null
    /** The PBX's answer to our offer: [provisional] for early media (183), final for the 200 OK. */
    fun remoteAnswer(remote: String, provisional: Boolean, done: (Boolean) -> Unit = {}) {
        // The 200 OK usually repeats the 183's SDP: setting it again is not needed
        if (!provisional && remote == lastRemote && pc.signalingState() == PeerConnection.SignalingState.STABLE) { done(true); return }
        lastRemote = remote
        val type = if (provisional) SessionDescription.Type.PRANSWER else SessionDescription.Type.ANSWER
        pc.setRemoteDescription(object : Sdp() {
            override fun onSetSuccess() { main.post { done(true) } }
            override fun onSetFailure(error: String?) { main.post { lastError = "remote answer: $error"; done(false) } }
        }, SessionDescription(type, withMids(remote)))
    }

    /** Our hold: we keep sending (the PBX plays music to them) but tell the PBX we do not want audio back. */
    fun setHold(held: Boolean) {
        transceiver?.direction = if (held) RtpTransceiver.RtpTransceiverDirection.SEND_ONLY else RtpTransceiver.RtpTransceiverDirection.SEND_RECV
    }

    fun setMuted(muted: Boolean) { if (!closed) track.setEnabled(!muted) }

    /** Off while an incoming call rings (its answer is made in advance): no microphone or sound until Answer. */
    fun setAudioActive(on: Boolean) { if (!closed) { pc.setAudioRecording(on); pc.setAudioPlayout(on) } }

    /** Keypad tone inside the audio (RFC 2833 telephone-event), like desk phones; FreeSWITCH ignores SIP INFO. */
    fun sendDigit(d: Char) {
        if (closed) return
        val dtmf = sender.dtmf() ?: return
        if (dtmf.canInsertDtmf()) dtmf.insertDtmf(d.toString(), 160, 80)
    }

    fun close() {
        if (closed) return
        closed = true
        Rtc.inUse--
        main.removeCallbacks(quiet); main.removeCallbacks(cap); gathered = null
        try { pc.dispose() } catch (_: RuntimeException) {}
        try { track.dispose() } catch (_: RuntimeException) {}
        try { source.dispose() } catch (_: RuntimeException) {}
    }

    private open class Sdp : SdpObserver {
        override fun onCreateSuccess(desc: SessionDescription) {}
        override fun onSetSuccess() {}
        override fun onCreateFailure(error: String?) {}
        override fun onSetFailure(error: String?) {}
    }
}
