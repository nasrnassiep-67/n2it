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

    fun factory(context: Context): PeerConnectionFactory = factory ?: run {
        PeerConnectionFactory.initialize(PeerConnectionFactory.InitializationOptions.builder(context.applicationContext)
            .createInitializationOptions())
        // The phone's own echo canceller and noise suppressor where it has them (tuned by the maker for its speaker and
        // microphones), WebRTC's software ones on top otherwise.
        val a = JavaAudioDeviceModule.builder(context.applicationContext)
            .setUseHardwareAcousticEchoCanceler(true)
            .setUseHardwareNoiseSuppressor(true)
            .createAudioDeviceModule()
        adm = a
        PeerConnectionFactory.builder().setAudioDeviceModule(a).createPeerConnectionFactory().also { factory = it }
    }
}

/**
 * The audio of one call. [onEnded] is called when the audio connection fails for good (network gone), so the call can
 * be hung up instead of staying silent.
 */
class CallMedia(context: Context, noiseFilter: Boolean, private val onFailed: () -> Unit) {
    private val main = Handler(Looper.getMainLooper())
    private val factory = Rtc.factory(context)
    private val source: AudioSource
    private val track: AudioTrack
    private val pc: PeerConnection
    private val transceiver: RtpTransceiver
    private var closed = false
    private var gathered: (() -> Unit)? = null
    private val quiet = Runnable { gatherDone() }
    private val cap = Runnable { gatherDone() }

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
            bundlePolicy = PeerConnection.BundlePolicy.MAXBUNDLE
            rtcpMuxPolicy = PeerConnection.RtcpMuxPolicy.REQUIRE
            tcpCandidatePolicy = PeerConnection.TcpCandidatePolicy.DISABLED
            continualGatheringPolicy = PeerConnection.ContinualGatheringPolicy.GATHER_ONCE
            keyType = PeerConnection.KeyType.ECDSA
        }
        pc = factory.createPeerConnection(cfg, observer) ?: error("WebRTC could not start")
        transceiver = pc.addTransceiver(track, RtpTransceiver.RtpTransceiverInit(
            RtpTransceiver.RtpTransceiverDirection.SEND_RECV, listOf("n2it")))
    }

    private val observer = object : PeerConnection.Observer {
        override fun onIceCandidate(candidate: IceCandidate) {
            // Like the desktop: go once candidates have been quiet for 1 s (a dead interface or slow STUN server
            // would otherwise hold the call up for ~40 s)
            main.post { if (gathered != null) { main.removeCallbacks(quiet); main.postDelayed(quiet, 1000) } }
        }
        override fun onIceGatheringChange(state: PeerConnection.IceGatheringState) {
            if (state == PeerConnection.IceGatheringState.COMPLETE) main.post { gatherDone() }
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

    private fun gatherDone() {
        main.removeCallbacks(quiet); main.removeCallbacks(cap)
        val g = gathered ?: return
        gathered = null
        if (!closed) g()
    }

    /** Our SDP once the candidates are in (or after 4 s at most). */
    private fun afterGathering(done: (String?) -> Unit) {
        if (pc.iceGatheringState() == PeerConnection.IceGatheringState.COMPLETE) { done(pc.localDescription?.description); return }
        gathered = { done(pc.localDescription?.description) }
        main.postDelayed(cap, 4000)
    }

    private fun setLocal(desc: SessionDescription, done: (String?) -> Unit) {
        pc.setLocalDescription(object : Sdp() {
            override fun onSetSuccess() { main.post { if (closed) done(null) else afterGathering(done) } }
            override fun onSetFailure(error: String?) { main.post { done(null) } }
        }, desc)
    }

    /** New call or re-INVITE from us: an offer with all our candidates; null if WebRTC could not make one. */
    fun offer(done: (String?) -> Unit) {
        pc.createOffer(object : Sdp() {
            override fun onCreateSuccess(desc: SessionDescription) { main.post { if (closed) done(null) else setLocal(desc, done) } }
            override fun onCreateFailure(error: String?) { main.post { done(null) } }
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
                        override fun onCreateFailure(error: String?) { main.post { done(null) } }
                    }, MediaConstraints())
                }
            }
            override fun onSetFailure(error: String?) { main.post { done(null) } }
        }, SessionDescription(SessionDescription.Type.OFFER, remote))
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
            override fun onSetFailure(error: String?) { main.post { done(false) } }
        }, SessionDescription(type, remote))
    }

    /** Our hold: we keep sending (the PBX plays music to them) but tell the PBX we do not want audio back. */
    fun setHold(held: Boolean) {
        transceiver.direction = if (held) RtpTransceiver.RtpTransceiverDirection.SEND_ONLY else RtpTransceiver.RtpTransceiverDirection.SEND_RECV
    }

    fun setMuted(muted: Boolean) { if (!closed) track.setEnabled(!muted) }

    /** Keypad tone inside the audio (RFC 2833 telephone-event), like desk phones; FreeSWITCH ignores SIP INFO. */
    fun sendDigit(d: Char) {
        if (closed) return
        val dtmf = transceiver.sender.dtmf() ?: return
        if (dtmf.canInsertDtmf()) dtmf.insertDtmf(d.toString(), 160, 80)
    }

    fun close() {
        if (closed) return
        closed = true
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
