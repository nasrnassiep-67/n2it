import Foundation
import WebRTC

/*
 * Call audio over WebRTC (Google's library, BSD licence; binaries from the stasel/WebRTC Swift package): G.722/G.711,
 * DTLS-SRTP encryption, echo cancellation and noise suppression (Apple's voice-processing unit). One PeerConnection per
 * call; the SDP goes to and from the PBX inside SIP (SipStack.swift), with all ICE candidates included (the PBX does not
 * do trickle ICE), like the desktop app and Android. Port of Android's CallMedia.kt.
 *
 * With CallKit the app owns the audio session only while CallKit says so: useManualAudio = true, and
 * RTCAudioSession.isAudioEnabled follows CallKit's didActivate / didDeactivate (CallKitManager).
 */
enum Rtc {
    static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let a = RTCAudioSession.sharedInstance()
        a.useManualAudio = true
        a.isAudioEnabled = false
        return RTCPeerConnectionFactory()
    }()
}

/// The audio of one call. `onFailed` is called when the audio connection fails for good (network gone), so the call can
/// be hung up instead of staying silent.
final class CallMedia: NSObject, RTCPeerConnectionDelegate {
    private let source: RTCAudioSource
    private let track: RTCAudioTrack
    private var pc: RTCPeerConnection!
    private var sender: RTCRtpSender!
    private let onFailed: () -> Void
    /// Test builds: "ICE connected, DTLS connected, in 1200 B / out 800 B" for the call screen.
    var onDiag: ((String) -> Void)?
    private var iceState = "new", pcState = "new"
    private var statsTimer: Timer?
    private var candidates = 0
    private var closed = false
    private var gathered: (() -> Void)?
    private var quiet: DispatchWorkItem?
    private var cap: DispatchWorkItem?
    private var lastRemote: String?
    /// WebRTC's own words for the last failure, for the tester to send to N2IT.
    private(set) var lastError: String?

    init?(noiseFilter: Bool, onFailed: @escaping () -> Void) {
        self.onFailed = onFailed
        let f = Rtc.factory
        let c = RTCMediaConstraints(mandatoryConstraints: [
            "googEchoCancellation": "true", "googAutoGainControl": "true",
            "googNoiseSuppression": noiseFilter ? "true" : "false", "googHighpassFilter": "true"], optionalConstraints: nil)
        source = f.audioSource(with: c)
        track = f.audioTrack(with: source, trackId: "n2it-mic")
        super.init()
        let cfg = RTCConfiguration()
        cfg.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        cfg.sdpSemantics = .unifiedPlan
        // Balanced, as browsers: FreeSWITCH offers no BUNDLE group, which max-bundle refuses ("no BUNDLE group")
        cfg.bundlePolicy = .balanced
        cfg.rtcpMuxPolicy = .require
        cfg.tcpCandidatePolicy = .disabled
        cfg.continualGatheringPolicy = .gatherOnce
        cfg.keyType = .ECDSA
        let pcConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: ["DtlsSrtpKeyAgreement": "true"])
        guard let pc = f.peerConnection(with: cfg, constraints: pcConstraints, delegate: self) else { return nil }
        self.pc = pc
        // add(track), not addTransceiver: only a track added this way is reused for the PBX's offer (JSEP); a transceiver
        // made separately is left aside and the call answered "recvonly" with no microphone (Android 0.3.0 test)
        sender = pc.add(track, streamIds: ["n2it"])
    }

    // MARK: RTCPeerConnectionDelegate
    func peerConnection(_ pc: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        DispatchQueue.main.async {
            self.candidates += 1
            // Go once candidates have been quiet for 0.5 s (a dead interface or slow STUN server would otherwise hold the
            // call up for ~40 s; 1 s added a second to every call)
            if self.gathered != nil { self.quiet?.cancel(); self.quiet = later(0.5) { [weak self] in self?.gatherDone() } }
        }
    }
    func peerConnection(_ pc: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        // "Complete" with no address at all is not done (Android 0.3.0: an answer with none, the PBX hung up): wait for the cap
        if newState == .complete { DispatchQueue.main.async { if self.candidates > 0 { self.gatherDone() } } }
    }
    func peerConnection(_ pc: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        pcState = "\(newState.rawValue)"
        if newState == .failed { DispatchQueue.main.async { if !self.closed { self.onFailed() } } }
    }
    func peerConnection(_ pc: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ pc: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ pc: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ pc: RTCPeerConnection) {}
    func peerConnection(_ pc: RTCPeerConnection, didChange newState: RTCIceConnectionState) { iceState = "\(newState.rawValue)" }
    func peerConnection(_ pc: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ pc: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}

    // MARK: SDP
    private func gatherDone() {
        quiet?.cancel(); cap?.cancel()
        guard let g = gathered else { return }
        gathered = nil
        if !closed { g() }
    }

    /// Our SDP once the candidates are in (or after 4 s at most).
    private func afterGathering(_ done: @escaping (String?) -> Void) {
        let result = { [weak self] in
            guard let self else { return }
            let sdp = self.pc.localDescription?.sdp
            if let sdp, !sdp.contains("a=candidate") { self.lastError = "no network address for the audio (ICE gathered nothing)"; done(nil) }
            else { done(sdp) }
        }
        if candidates > 0 && pc.iceGatheringState == .complete { result(); return }
        gathered = result
        cap?.cancel(); cap = later(4) { [weak self] in self?.gatherDone() }
    }

    private func setLocal(_ desc: RTCSessionDescription, _ done: @escaping (String?) -> Void) {
        pc.setLocalDescription(desc) { [weak self] err in
            DispatchQueue.main.async {
                guard let self else { return }
                if let err { self.lastError = "local: \(err.localizedDescription)"; done(nil) }
                else if self.closed { done(nil) }
                else { self.afterGathering(done) }
            }
        }
    }

    /// New call or re-INVITE from us: an offer with all our candidates; nil if WebRTC could not make one.
    func offer(_ done: @escaping (String?) -> Void) {
        pc.offer(for: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)) { [weak self] desc, err in
            DispatchQueue.main.async {
                guard let self else { return }
                if let desc, !self.closed { self.setLocal(desc, done) }
                else { self.lastError = "offer: \(err?.localizedDescription ?? "closed")"; done(nil) }
            }
        }
    }

    /// The PBX's offer (incoming call, or its re-INVITE): our answer, or nil if the offer cannot be used.
    func answer(_ remote: String, _ done: @escaping (String?) -> Void) {
        pc.setRemoteDescription(RTCSessionDescription(type: .offer, sdp: withMids(remote))) { [weak self] err in
            DispatchQueue.main.async {
                guard let self else { return }
                if let err { self.lastError = "remote offer: \(err.localizedDescription)"; done(nil); return }
                if self.closed { done(nil); return }
                self.pc.answer(for: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)) { desc, err in
                    DispatchQueue.main.async {
                        if let desc, !self.closed { self.setLocal(desc, done) }
                        else { self.lastError = "answer: \(err?.localizedDescription ?? "closed")"; done(nil) }
                    }
                }
            }
        }
    }

    /// FreeSWITCH's SDP has no a=mid (old-style WebRTC); newer WebRTC wants one per m= line: 0, 1, … in order.
    private func withMids(_ sdp: String) -> String {
        if sdp.contains("a=mid:") { return sdp }
        var i = 0
        return sdp.components(separatedBy: "\r\n").map { line -> String in
            if line.hasPrefix("m=") { defer { i += 1 }; return "\(line)\r\na=mid:\(i)" }
            return line
        }.joined(separator: "\r\n")
    }

    /// The PBX's answer to our offer: `provisional` for early media (183), final for the 200 OK.
    func remoteAnswer(_ remote: String, provisional: Bool, _ done: @escaping (Bool) -> Void = { _ in }) {
        // The 200 OK usually repeats the 183's SDP: setting it again is not needed
        if !provisional && remote == lastRemote && pc.signalingState == .stable { done(true); return }
        lastRemote = remote
        pc.setRemoteDescription(RTCSessionDescription(type: provisional ? .prAnswer : .answer, sdp: withMids(remote))) { [weak self] err in
            DispatchQueue.main.async {
                if let err { self?.lastError = "remote answer: \(err.localizedDescription)"; done(false) } else { done(true) }
            }
        }
    }

    // MARK: In the call
    private var transceiver: RTCRtpTransceiver? { pc.transceivers.first { $0.sender.senderId == sender.senderId } }

    /// Our hold: we keep sending (the PBX plays music to them) but tell the PBX we do not want audio back.
    func setHold(_ held: Bool) {
        var err: NSError?
        transceiver?.setDirection(held ? .sendOnly : .sendRecv, error: &err)
    }

    func setMuted(_ muted: Bool) { if !closed { track.isEnabled = !muted } }

    /// Keypad tone inside the audio (RFC 2833 telephone-event), like desk phones; FreeSWITCH ignores SIP INFO.
    func sendDigit(_ d: Character) {
        guard !closed, let dtmf = sender.dtmfSender, dtmf.canInsertDtmf else { return }
        dtmf.insertDtmf(String(d), duration: 0.16, interToneGap: 0.08)
    }

    /// ice/pc states are RTCIceConnectionState / RTCPeerConnectionState raw values (2 = connected / 1 = checking …).
    func startDiag() {
        statsTimer?.invalidate()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, !self.closed else { return }
            self.pc.statistics { report in
                var inB = 0, outB = 0, inLost = 0
                var codec = ""
                for st in report.statistics.values {
                    if st.type == "inbound-rtp", st.values["kind"] as? String == "audio" {
                        inB = (st.values["bytesReceived"] as? NSNumber)?.intValue ?? 0
                        inLost = (st.values["packetsLost"] as? NSNumber)?.intValue ?? 0
                    }
                    if st.type == "outbound-rtp", st.values["kind"] as? String == "audio" { outB = (st.values["bytesSent"] as? NSNumber)?.intValue ?? 0 }
                    if st.type == "codec", let m = st.values["mimeType"] as? String { codec = m }
                }
                let line = "audio: ice \(self.iceState) pc \(self.pcState) \(codec) in \(inB) B (lost \(inLost)) out \(outB) B"
                DispatchQueue.main.async { self.onDiag?(line) }
            }
        }
    }

    func close() {
        if closed { return }
        closed = true
        statsTimer?.invalidate()
        quiet?.cancel(); cap?.cancel(); gathered = nil
        pc.close()
    }
}
