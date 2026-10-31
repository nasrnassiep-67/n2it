package za.co.n2it.phone

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.ConnectivityManager
import android.net.Network
import android.os.Build
import android.media.ToneGenerator
import android.os.Handler
import android.os.Looper
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeoutOrNull

/** Where a call is; the names are the ones the screens and the notification have always used. */
enum class CallState {
    IncomingReceived, OutgoingInit, OutgoingProgress, OutgoingRinging, OutgoingEarlyMedia,
    Connected, StreamsRunning, Pausing, Paused, Resuming, PausedByRemote, End, Error, Released
}

data class CallInfo(val number: String, val state: CallState, val incoming: Boolean, val onHold: Boolean = false, val consulting: Boolean = false,
                    val conference: Boolean = false, val participants: List<Participant> = emptyList(), val name: String? = null)
/** One other person in a conference (the conference screen gives each one a card). [id] is the SIP Call-ID. */
/** [name] is the caller ID name the PBX sent (e.g. "Nasr" for 1002), when there is one. */
data class Participant(val id: String, val number: String, val status: Status, val name: String? = null) {
    enum class Status { Talking, Ringing, OnHold }
}
data class RecentCall(val number: String, val time: Long, val incoming: Boolean, val missed: Boolean)

/** Where call audio goes: the phone's earpiece, the loudspeaker, a Bluetooth device (car kit, headset) or a wired headset. */
enum class AudioRoute { Earpiece, Speaker, Bluetooth, Headset }
/** A route the phone can use right now; [name] is the device's own name for Bluetooth ("VW BT 1234"). */
data class AudioOption(val route: AudioRoute, val name: String)

/** One call: its SIP dialog and its audio. */
private class Call(val incoming: Boolean, val callId: String, val number: String, val name: String?) {
    var state = if (incoming) CallState.IncomingReceived else CallState.OutgoingInit
    val localTag = java.util.UUID.randomUUID().toString().take(10)
    /** Outgoing: our INVITE (kept for CANCEL, replaced by the password retry). Incoming: the PBX's INVITE. */
    var invite: SipMsg? = null
    var dialog: Dialog? = null
    var media: CallMedia? = null
    var connectedAt = 0L
    var answered = false
    var answering = false
    /** Answered on another phone of the extension (the PBX's CANCEL says so): not a missed call. */
    var elsewhere = false
    var gotProvisional = false
    var earlyMedia = false
    /** Hang up asked for before the PBX answered anything: CANCEL as soon as it does. */
    var hangupWanted = false
    var localHold = false
    var remoteHold = false
    var reinviting = false
    /** Blind or attended transfer sent (REFER): hang up once the PBX says it worked. */
    var transferring = false
    /** Rung from a conference (Add participant): moved into the room as soon as they answer. */
    var autoMerge = false
    /** Incoming: our answer SDP, made while it rings (null = could not be made); [prepareDone] once that finished. */
    var prepared: String? = null
    var prepareDone = false
}

object SipManager : SipUa.Events {
    private var started = false
    lateinit var appContext: Context; private set
    private lateinit var ua: SipUa
    private lateinit var router: AudioRouter
    private val calls = mutableListOf<Call>()

    private val _registered = MutableStateFlow(false)
    /** The PBX's answer to the latest registration, for the sign-in check (null = no answer yet). */
    sealed interface RegOutcome { object Ok : RegOutcome; data class Failed(val code: Int, val reason: String) : RegOutcome }
    private val _outcome = MutableStateFlow<RegOutcome?>(null)
    private val _status = MutableStateFlow("Not registered")
    private val _call = MutableStateFlow<CallInfo?>(null)
    private val _muted = MutableStateFlow(false)
    private val _route = MutableStateFlow(AudioRoute.Earpiece)
    private val _routes = MutableStateFlow<List<AudioOption>>(emptyList())
    private val _recents = MutableStateFlow<List<RecentCall>>(emptyList())
    private val _voicemail = MutableStateFlow(false)
    private val _silenced = MutableStateFlow(false)
    /** The ringing call was silenced (Silence button, volume key): it keeps ringing for the caller, quietly here. */
    val silenced: StateFlow<Boolean> = _silenced
    private val _echo = MutableStateFlow("Automatic: no tuning needed")
    /** Echo cancellation status for the Settings screen. WebRTC's canceller adapts by itself during each call. */
    val echo: StateFlow<String> = _echo
    private val _gate = MutableStateFlow(true)
    /** "Filter out background voices" (Settings): WebRTC's noise suppression on the microphone. */
    val backgroundFilter: StateFlow<Boolean> = _gate
    val registered: StateFlow<Boolean> = _registered
    /** The PBX refused the saved extension/password (not during a sign-in check): the app goes back to the sign-in screen. */
    private val _refused = MutableStateFlow(false)
    val refused: StateFlow<Boolean> = _refused
    fun clearRefused() { _refused.value = false }
    private var verifying = false
    val status: StateFlow<String> = _status
    val call: StateFlow<CallInfo?> = _call
    val muted: StateFlow<Boolean> = _muted
    val audioRoute: StateFlow<AudioRoute> = _route
    val audioRoutes: StateFlow<List<AudioOption>> = _routes
    val recents: StateFlow<List<RecentCall>> = _recents
    val hasVoicemail: StateFlow<Boolean> = _voicemail

    private val ended = setOf(CallState.End, CallState.Error, CallState.Released)
    private fun liveCalls(except: Call? = null) = calls.filter { it !== except && it.state !in ended }
    /** A call of ours that is up (not just ringing in). */
    fun hasActiveCall() = started && liveCalls().any { it.state != CallState.IncomingReceived }
    /** The call in front of the user: the one not on hold. */
    private fun currentCall() = liveCalls().firstOrNull { it.state != CallState.IncomingReceived && !it.localHold }
    private fun ringingCall() = liveCalls().firstOrNull { it.state == CallState.IncomingReceived && !it.answering }

    /** Mirror the calls into UI state: one call, or a held call plus a consult call. */
    private fun publish() {
        updateProximity()
        val conf = confCall?.takeIf { it.state !in ended }
        if (conf != null) {
            val others = liveCalls().filter { it !== conf && !it.transferring }
            val ringing = others.map { Participant(it.callId, it.number,
                if (it.answered) Participant.Status.OnHold else Participant.Status.Ringing, it.name) }
            val people = confPeople + ringing
            _call.value = CallInfo(people.joinToString(", ") { it.name ?: it.number }, conf.state, false,
                conf.localHold, consulting = others.any { it.answered && !it.autoMerge }, conference = true, participants = people)
            return
        }
        val live = liveCalls().filter { !it.transferring || liveCalls().size == 1 }
        val c = currentCall() ?: ringingCall() ?: live.firstOrNull()
        if (c == null) { _call.value = null; return }
        _call.value = CallInfo(c.number, c.state, c.incoming, c.state == CallState.Paused || c.state == CallState.Pausing,
            live.size > 1, name = c.name)
    }

    private fun setState(c: Call, s: CallState) {
        c.state = s
        when (s) {
            CallState.OutgoingInit, CallState.Connected -> {
                // Outgoing call placed, or incoming call answered: the user is in the app right now,
                // so this is when Android lets the service take the microphone.
                PhoneService.setInCall(appContext, true)
                router.startCall()
                // Audio focus from the moment the user places the call (2026-10-31: music kept playing while an
                // outgoing call rang out on the HONOR; it only paused at the answer). Incoming calls still take it at
                // the answer, so a ringing call never takes the audio from another app's call in progress.
                takeFocus()
                // First call: Bluetooth if connected (car, headset), else a wired headset, else the earpiece.
                if (!routeChosen) { routeChosen = true; updateRoutes(); _route.value = defaultRoute() }
                applyRoute()
            }
            CallState.StreamsRunning -> {
                applyRoute()
                if (c === confCall && pendingMerge.isNotEmpty()) { val list = pendingMerge.toList(); pendingMerge.clear(); moveIntoRoom(list) }
                if (c.autoMerge && confCall != null) { c.autoMerge = false; moveIntoRoom(listOf(c)) }
            }
            else -> {}
        }
        if (s != CallState.IncomingReceived && liveCalls().none { it.state == CallState.IncomingReceived }) stopQuietRing()
        publish()
    }

    /** Safe to call repeatedly; the service and the activity both call it. */
    @Synchronized
    fun init(context: Context) {
        if (started) return
        appContext = context.applicationContext
        CrashLog.install(appContext)
        ua = SipUa(this)
        // Shows on the PBX (registrations, logs) instead of "Unknown".
        ua.userAgent = "N2IT Phone Android/${BuildConfig.VERSION_NAME}"
        router = AudioRouter(appContext) { onDevicesChanged() }
        _gate.value = appContext.getSharedPreferences("n2it_echo", Context.MODE_PRIVATE).getBoolean("gate", true)
        _hwAec.value = Rtc.hwAec(appContext)
        _tester.value = isTester(appContext)
        started = true
        updateRoutes()
        watchNetwork()
        setDnd(dndPrefs().getLong("until", 0).takeIf { it > 0 })   // survives restarts; clears itself if expired
        configure(Account.load(appContext))
    }

    /** Wi-Fi <-> mobile data: the old connection is dead; reconnect at once so calls keep ringing. */
    private var network: Network? = null
    private fun watchNetwork() {
        val cm = appContext.getSystemService(ConnectivityManager::class.java) ?: return
        try { cm.registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(n: Network) {
                main.post {
                    val changed = network != null && network != n
                    network = n
                    if (changed) ua.reconnectNow()
                }
            }
        }) } catch (e: SecurityException) { /* no network permission: reconnects happen on the next failure instead */ }
    }

    // ---- Registration ----
    override fun onRegistration(state: SipUa.RegState, code: Int, reason: String) {
        _registered.value = state == SipUa.RegState.Ok
        when (state) {
            SipUa.RegState.Ok -> { _outcome.value = RegOutcome.Ok; subscribeVoicemail() }
            SipUa.RegState.Failed -> {
                _outcome.value = RegOutcome.Failed(code, reason)
                if (!verifying && code in setOf(401, 403, 407)) { ua.stop(); _refused.value = true }   // never retried: 5 wrong passwords and the PBX bans the network
            }
            else -> {}
        }
        _status.value = when (state) {
            SipUa.RegState.Ok -> "Registered"
            SipUa.RegState.Progress -> reason.ifEmpty { "Registering…" }
            SipUa.RegState.Failed -> "Failed: $reason"
            SipUa.RegState.None -> "Not registered"
        }
    }

    override fun onTransportDown() {
        // Calls cannot be controlled without the connection; their audio may still flow and the PBX keeps them up.
        mwiTimer.let { main.removeCallbacks(it) }
    }

    /**
     * Sign-in check: registers [acc] and waits for the PBX's answer, so a wrong extension or password is said at once
     * instead of the app opening with a red "Failed: Forbidden". null = no answer within [timeoutMs] (wrong company code,
     * no internet). After a refusal the caller stops it ([stopRegistering]) or puts the previous account back: retrying a
     * wrong password every minute gets the phone's whole network banned by the PBX (fail2ban).
     */
    suspend fun verify(acc: za.co.n2it.phone.Account, timeoutMs: Long = 12_000): RegOutcome? {
        if (!started) return null
        _outcome.value = null
        verifying = true
        try {
            configure(acc)
            return withTimeoutOrNull(timeoutMs) { _outcome.first { it != null } }
        } finally { verifying = false }
    }

    fun stopRegistering() { if (started) ua.stop() }

    /** Register [acc] over the secure WebSocket at wss://<company>.voip.n2it.co.za/wss (port 443, as the desktop app).
     *  The account's port and transport (5061/TLS) were for Linphone and are not used. */
    fun configure(acc: za.co.n2it.phone.Account) {
        if (!started || !acc.isConfigured) return
        ua.start(acc.user, acc.password, acc.domain)
    }

    // ---- Voicemail lamp: SUBSCRIBE message-summary; the PBX NOTIFYs "Messages-Waiting: yes" / "Voice-Message: 2/0" ----
    private val mwiTimer = Runnable { subscribeVoicemail() }
    private var mwiCallId = ""
    private fun subscribeVoicemail() {
        main.removeCallbacks(mwiTimer)
        if (mwiCallId.isEmpty()) mwiCallId = ua.token(22)
        val sub = SipMsg("SUBSCRIBE ${ua.aor} SIP/2.0").add("Via", ua.via()).add("Max-Forwards", "70")
            .add("To", "<${ua.aor}>").add("From", "<${ua.aor}>;tag=${ua.token(10)}").add("Call-ID", mwiCallId)
            .add("CSeq", "${++mwiCseq} SUBSCRIBE").add("Contact", ua.contact).add("Event", "message-summary")
            .add("Accept", "application/simple-message-summary").add("Expires", "3600").add("User-Agent", ua.userAgent)
        ua.request(sub, onRetry = { mwiCseq = it.cseq }) { res -> if (res.status in 200..299) main.postDelayed(mwiTimer, 3000_000L) }
    }
    private var mwiCseq = 0

    /** Another saved account becomes active: what was shown belongs to the previous one. */
    fun switchAccount(acc: za.co.n2it.phone.Account) {
        _recents.value = emptyList(); _voicemail.value = false; _registered.value = false; _status.value = "Registering…"
        configure(acc)
    }

    fun signOut(context: Context) {
        if (started) ua.stop()
        za.co.n2it.phone.Account.clear(context)
        _registered.value = false; _status.value = "Not registered"; _recents.value = emptyList(); _voicemail.value = false
    }

    // ---- Requests from the PBX ----
    override fun onRequest(req: SipMsg) {
        val c = calls.firstOrNull { it.callId == req.callId && it.state !in ended }
        when (req.method) {
            "INVITE" -> if (c == null) {
                if (req.toTag != null) ua.reply(req, 481, "Call/Transaction Does Not Exist") else incoming(req)
            } else offerFromPbx(c, req)
            "ACK" -> {}
            "CANCEL" -> {
                ua.reply(req, 200, "OK")
                if (c == null || c.answered) return
                c.invite?.let { ua.reply(it, 487, "Request Terminated", c.localTag) }
                // Answered on another phone of the extension: the PBX says "Call completed elsewhere" (cause 200)
                val why = req.h("Reason") ?: ""
                c.elsewhere = why.contains("cause=200") || why.contains("elsewhere", true)
                end(c)
            }
            "BYE" -> { ua.reply(req, 200, "OK"); c?.let { end(it) } }
            "UPDATE" -> if (c != null && req.hasSdp) offerFromPbx(c, req) else ua.reply(req, 200, "OK", extra = listOf("Contact" to ua.contact))
            "NOTIFY" -> { ua.reply(req, 200, "OK"); notify(req) }
            "OPTIONS" -> ua.reply(req, 200, "OK", extra = listOf("Allow" to SipUa.ALLOW, "Accept" to "application/sdp"))
            "INFO", "MESSAGE" -> ua.reply(req, 200, "OK")
            else -> ua.reply(req, 501, "Not Implemented")
        }
    }

    private fun notify(req: SipMsg) {
        val event = (req.h("Event") ?: "").substringBefore(';').trim()
        if (event.equals("message-summary", true)) {
            val text = req.body
            val waiting = Regex("Messages-Waiting:\\s*yes", RegexOption.IGNORE_CASE).containsMatchIn(text)
            val newCount = Regex("Voice-Message:\\s*(\\d+)/", RegexOption.IGNORE_CASE).find(text)?.groupValues?.get(1)?.toIntOrNull() ?: 0
            _voicemail.value = waiting || newCount > 0
            return
        }
        if (!event.equals("refer", true)) return
        // How the transfer is going: "SIP/2.0 200 OK" when the other side answered
        val c = calls.firstOrNull { it.callId == req.callId && it.transferring } ?: return
        val code = Regex("SIP/2.0\\s+(\\d{3})").find(req.body)?.groupValues?.get(1)?.toIntOrNull() ?: return
        when {
            code in 200..299 -> hangupCall(c)
            code >= 300 -> { c.transferring = false; _notice.value = "Transfer failed ($code)" }
        }
    }

    private fun incoming(req: SipMsg) {
        val from = req.h("From")
        val number = SipMsg.userOf(SipMsg.uriOf(from)).ifEmpty { "Unknown" }
        val name = SipMsg.nameOf(from)?.takeIf { it != number }
        checkDnd()
        if (dndActive()) {
            // DND: refuse as busy; the PBX sends the caller to voicemail (or says there is none).
            // Other phones on the same extension (e.g. a desk phone) keep ringing.
            ua.reply(req, 486, "Busy Here", ua.token(10))
            addRecent(number, incoming = true, missed = true)
            return
        }
        if (!req.hasSdp) { ua.reply(req, 488, "Not Acceptable Here", ua.token(10)); return }
        val c = Call(true, req.callId, number, name)
        c.invite = req
        c.dialog = Dialog(req.callId, c.localTag, req.fromTag ?: "", SipMsg.uriOf(req.h("To")), SipMsg.uriOf(from),
            SipMsg.uriOf(req.h("Contact")).ifEmpty { SipMsg.uriOf(from) }, req.all("Record-Route").flatMap { it.split(',') }.map { it.trim() },
            localCseq = 1, remoteName = name)
        calls += c
        ua.reply(req, 180, "Ringing", c.localTag, listOf("Contact" to ua.contact))
        // On a GSM / WhatsApp call (or one of ours): no ringtone over that call, a call-waiting beep in the earpiece
        // instead (owner 2026-10-08). The notification still offers Answer, Decline and Silence.
        val busy = PhoneService.otherAppInCall(appContext) || hasActiveCall()
        _silenced.value = false
        PhoneService.notifyIncoming(appContext, name?.let { "$it ($number)" } ?: number, busy)
        if (busy) quietRing() else { startRingtone(); startVibrate() }
        publish()
        // Make the answer while it rings (0.3.1 test 2026-10-22: about 2 s of silence after Answer while WebRTC gathered
        // its addresses). Microphone and speaker stay off until Answer. That switch is shared by every call (WebRTC's
        // audio state), so it is left alone when another call is up: turning it off would silence that call.
        val media = newMedia(c)
        if (!hasActiveCall()) media.setAudioActive(false)
        media.answer(req.body) { sdp ->
            if (c.state in ended) return@answer
            c.prepared = sdp; c.prepareDone = true
            if (c.answering) sendAnswer(c)
        }
    }

    /** The PBX's offer inside a call (its re-INVITE or UPDATE): hold by them, music on hold, a transfer on its side. */
    private fun offerFromPbx(c: Call, req: SipMsg) {
        val media = c.media
        if (media == null || !req.hasSdp) {
            ua.reply(req, if (req.hasSdp) 491 else 488, if (req.hasSdp) "Request Pending" else "Not Acceptable Here", c.localTag); return
        }
        if (c.reinviting) { ua.reply(req, 491, "Request Pending", c.localTag); return }
        req.h("Contact")?.let { ct -> c.dialog?.remoteTarget = SipMsg.uriOf(ct) }
        val heldByThem = Regex("a=(sendonly|inactive)").containsMatchIn(req.body) || req.body.contains("c=IN IP4 0.0.0.0")
        media.answer(req.body) { sdp ->
            if (c.state in ended) return@answer
            if (sdp == null) { ua.reply(req, 488, "Not Acceptable Here", c.localTag); problem("PBX re-offer refused: ${media.lastError}", req.body); return@answer }
            ua.reply(req, 200, "OK", c.localTag, listOf("Contact" to ua.contact, "Allow" to SipUa.ALLOW), sdp)
            c.remoteHold = heldByThem
            if (!c.localHold) setState(c, if (heldByThem) CallState.PausedByRemote else CallState.StreamsRunning)
        }
    }

    // ---- Calls ----
    /** Rings [number]; false when it could not be dialled (not connected, or not a valid number). */
    fun call(number: String): Boolean = startCall(number) != null

    private fun startCall(number: String): Call? {
        val n = cleanNumber(number)
        if (!started || n.isBlank() || !ua.connected) return null
        val target = if ('@' in n) "sip:$n" else "sip:$n@${ua.domain}"
        val c = Call(false, ua.token(22), SipMsg.userOf(target), null)
        calls += c
        _muted.value = _muted.value && liveCalls().size > 1
        setState(c, CallState.OutgoingInit)
        val media = newMedia(c)
        media.offer { sdp ->
            if (c.state in ended) return@offer
            if (sdp == null) problem("Call failed: ${c.media?.lastError ?: "no audio"}", null)
            if (sdp == null || c.hangupWanted) { fail(c, if (sdp == null) "No audio" else null); return@offer }
            val inv = SipMsg("INVITE $target SIP/2.0").add("Via", ua.via()).add("Max-Forwards", "70")
                .add("To", "<$target>").add("From", "<${ua.aor}>;tag=${c.localTag}").add("Call-ID", c.callId)
                .add("CSeq", "1 INVITE").add("Contact", ua.contact).add("Allow", SipUa.ALLOW)
                .add("Supported", "replaces, outbound").add("User-Agent", ua.userAgent).add("Content-Type", "application/sdp")
            inv.body = sdp
            c.invite = inv
            ua.request(inv, onRetry = { c.invite = it }) { res -> inviteAnswered(c, target, res) }
        }
        return c
    }

    private fun newMedia(c: Call) = CallMedia(appContext, _gate.value) {
        // The audio connection failed for good (network gone): end the call instead of leaving it silent
        if (c.state !in ended) { _notice.value = "Call audio lost"; hangupCall(c) }
    }.also { c.media = it; it.setMuted(_muted.value); it.setAudioActive(true) }

    private fun inviteAnswered(c: Call, target: String, res: SipMsg) {
        if (c.state in ended) {
            if (res.status in 200..299) { dialogFrom(c, target, res); ack(c, res); c.dialog?.let { ua.request(ua.inDialog(it, "BYE")) {} } }
            return
        }
        when {
            res.status < 200 -> {
                if (res.status > 100) {
                    c.gotProvisional = true
                    if (c.hangupWanted) { c.invite?.let { ua.cancel(it) }; return }
                }
                when {
                    res.hasSdp -> c.media?.remoteAnswer(res.body, provisional = true) { ok ->
                        if (!ok) problem("Early media refused: ${c.media?.lastError}", res.body)
                        if (ok && c.state !in ended && !c.answered) { c.earlyMedia = true; stopRingback(); setState(c, CallState.OutgoingEarlyMedia) }
                    }
                    res.status == 180 -> { if (!c.earlyMedia) { startRingback(); setState(c, CallState.OutgoingRinging) } }
                    res.status > 100 && c.state == CallState.OutgoingInit -> setState(c, CallState.OutgoingProgress)
                    res.status == 100 -> setState(c, CallState.OutgoingProgress)
                }
            }
            res.status < 300 -> {
                stopRingback()
                dialogFrom(c, target, res)
                ack(c, res)
                c.answered = true; c.connectedAt = System.currentTimeMillis()
                if (res.hasSdp) c.media?.remoteAnswer(res.body, provisional = false) { ok ->
                    if (!ok) problem("Answer from PBX refused: ${c.media?.lastError}", res.body)
                }
                setState(c, CallState.Connected)
                setState(c, CallState.StreamsRunning)
                if (c.hangupWanted) hangupCall(c)
            }
            else -> fail(c, when (res.status) {
                486, 600 -> "Busy"; 480 -> "Not available"; 404, 484 -> "Number not found"; 487 -> null
                403 -> "Not allowed"; 408 -> "No answer"; 488 -> "Audio not accepted"; 503 -> res.reason.ifEmpty { "Not connected" }
                else -> "${res.status} ${res.reason}".trim()
            })
        }
    }

    private fun dialogFrom(c: Call, target: String, res: SipMsg) {
        if (c.dialog != null) return
        c.dialog = Dialog(c.callId, c.localTag, res.toTag ?: "", ua.aor, SipMsg.uriOf(res.h("To")).ifEmpty { target },
            SipMsg.uriOf(res.h("Contact")).ifEmpty { target },
            res.all("Record-Route").flatMap { it.split(',') }.map { it.trim() }.reversed(), localCseq = c.invite?.cseq ?: 1)
    }

    private fun ack(c: Call, res: SipMsg) { c.dialog?.let { ua.send(ua.inDialog(it, "ACK", res.cseq)) } }

    /** The call could not be made: say why (busy, rejected…) on the call screen instead of it just vanishing. */
    private fun fail(c: Call, why: String?) {
        stopRingback()
        if (why != null) _notice.value = "Call failed: $why"
        c.state = CallState.Error
        end(c)
    }

    fun answer() {
        val c = ringingCall() ?: return
        c.answering = true
        stopQuietRing(); PhoneService.clearIncoming(appContext)
        _muted.value = _muted.value && hasActiveCall()
        setState(c, CallState.Connected)
        c.media?.setMuted(_muted.value)
        c.media?.setAudioActive(true)
        if (c.prepareDone) sendAnswer(c)   // otherwise sent the moment the answer is ready
    }

    /** The answer made while it rang goes to the PBX: the call connects at once. */
    private fun sendAnswer(c: Call) {
        val req = c.invite ?: return
        if (c.answered || c.state in ended) return
        val sdp = c.prepared
        if (sdp == null) {
            ua.reply(req, 488, "Not Acceptable Here", c.localTag)
            problem("Answer failed: ${c.media?.lastError ?: "no audio"}", req.body)
            end(c); return
        }
        ua.reply(req, 200, "OK", c.localTag, listOf("Contact" to ua.contact, "Allow" to SipUa.ALLOW, "Supported" to "replaces, outbound"), sdp)
        c.answered = true; c.answering = false; c.connectedAt = System.currentTimeMillis()
        setState(c, CallState.StreamsRunning)
    }

    /** Decline the ringing call: the PBX carries on (other phones of the extension, voicemail). */
    fun decline() {
        val c = ringingCall() ?: return
        c.invite?.let { ua.reply(it, 603, "Decline", c.localTag) }
        stopQuietRing(); PhoneService.clearIncoming(appContext)
        end(c)
    }

    /** Ends the call in front of the user (or the ringing one). */
    fun hangup() {
        val c = currentCall() ?: liveCalls().firstOrNull() ?: return
        if (c.state == CallState.IncomingReceived && !c.answering) decline() else hangupCall(c)
    }

    private fun hangupCall(c: Call) {
        if (c.state in ended) return
        when {
            c.answered -> c.dialog?.let { ua.request(ua.inDialog(it, "BYE")) {} }
            c.incoming -> c.invite?.let { ua.reply(it, 603, "Decline", c.localTag) }
            c.gotProvisional -> c.invite?.let { ua.cancel(it) }
            // Nothing heard from the PBX yet: CANCEL (or BYE) as soon as it answers
            else -> { c.hangupWanted = true; if (c.invite != null) return }
        }
        end(c)
    }

    /** Conference: someone still being rung can be hung up; people already in the room are mixed by the PBX and can
     *  only leave themselves (hanging up ourselves leaves the others talking). */
    fun dropParticipant(id: String) {
        val c = liveCalls().firstOrNull { it.callId == id && it !== confCall }
        if (c != null) { hangupCall(c); return }
        _notice.value = "They are in the conference room: they can hang up themselves"
    }

    private fun end(c: Call) {
        if (c.state != CallState.Error) c.state = CallState.End
        c.media?.setAudioActive(true)   // a call that rang unanswered must not leave the shared microphone switch off
        c.media?.close(); c.media = null
        calls.remove(c)
        val missed = c.incoming && !c.answered && !c.elsewhere
        addRecent(c.number, c.incoming, missed)
        if (c.incoming && !c.answered) PhoneService.clearIncoming(appContext)
        if (ringingCall() == null) stopQuietRing()
        if (calls.none { it.state == CallState.OutgoingRinging }) stopRingback()
        userHeld.remove(c)
        consultHoldDone(c)
        if (c === confCall) { confCall = null; confRoom = null; confPeople.clear(); pendingMerge.clear()
            liveCalls().forEach { it.autoMerge = false } }
        if (c.autoMerge) confCall?.media?.setMuted(_muted.value)
        // Another call may still be up (held caller after a consult)
        if (liveCalls().isEmpty()) {
            _call.value = null; _muted.value = false; routeChosen = false
            router.endCall(); releaseFocus(); updateProximity()
            PhoneService.setInCall(appContext, false)
        } else publish()
    }

    private fun addRecent(number: String, incoming: Boolean, missed: Boolean) {
        _recents.value = listOf(RecentCall(number, System.currentTimeMillis(), incoming, missed)) + _recents.value
    }

    /** "082 123-4567", "(012) 345 6789" → digits; a typed SIP address (with @) is only trimmed. */
    fun cleanNumber(number: String) = number.trim().let { n -> if ('@' in n) n.filterNot { it.isWhitespace() } else n.filter { it in "+0123456789*#" } }

    private val _problem = MutableStateFlow<String?>(null)
    /** Test builds: the last call problem in WebRTC's own words (Settings shows it with Copy). */
    val lastProblem: StateFlow<String?> = _problem
    private fun problem(what: String, sdp: String?) {
        _problem.value = "N2IT Phone ${BuildConfig.VERSION_NAME}, ${java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.US).format(java.util.Date())}\n$what" +
            (sdp?.let { "\n--- SDP from PBX ---\n$it" } ?: "")
        if (_tester.value) android.widget.Toast.makeText(appContext, what, android.widget.Toast.LENGTH_LONG).show()
    }

    // Tester tools (Last call problem, error pop-ups, crash report): hidden from clients (owner 2026-10-22); tapping the
    // version number in Settings 7 times turns them on or off on this phone.
    private val _tester = MutableStateFlow(false)
    val testerMode: StateFlow<Boolean> = _tester
    fun isTester(context: Context) = context.getSharedPreferences("n2it", Context.MODE_PRIVATE).getBoolean("tester", false)
    fun setTesterMode(on: Boolean) {
        _tester.value = on
        appContext.getSharedPreferences("n2it", Context.MODE_PRIVATE).edit().putBoolean("tester", on).apply()
    }

    private val _notice = MutableStateFlow<String?>(null)
    /** A short message for the call screen (e.g. the second call could not be placed); cleared by the screen. */
    val notice: StateFlow<String?> = _notice
    fun clearNotice() { _notice.value = null }

    fun sendDigit(d: Char) { currentCall()?.media?.sendDigit(d) }
    fun toggleMute() { _muted.value = !_muted.value; liveCalls().forEach { it.media?.setMuted(_muted.value) } }

    // ---- Hold: re-INVITE with our audio "sendonly"; the PBX plays music on hold to the other side ----
    private fun setHold(c: Call, held: Boolean, done: (Boolean) -> Unit = {}) {
        val d = c.dialog; val media = c.media
        if (d == null || media == null || !c.answered || c.reinviting || c.localHold == held) { done(false); return }
        c.reinviting = true
        c.localHold = held
        setState(c, if (held) CallState.Pausing else CallState.Resuming)
        media.setHold(held)
        media.offer { sdp ->
            if (c.state in ended) { c.reinviting = false; done(false); return@offer }
            if (sdp == null) { c.reinviting = false; undoHold(c, held); done(false); return@offer }
            val req = ua.inDialog(d, "INVITE").add("Allow", SipUa.ALLOW).add("Content-Type", "application/sdp")
            req.body = sdp
            ua.request(req, onRetry = { d.localCseq = it.cseq }) { res ->
                if (res.status < 200) return@request
                c.reinviting = false
                if (c.state in ended) return@request
                if (res.status < 300) {
                    ua.send(ua.inDialog(d, "ACK", res.cseq))
                    if (res.hasSdp) media.remoteAnswer(res.body, provisional = false)
                    setState(c, if (held) CallState.Paused else if (c.remoteHold) CallState.PausedByRemote else CallState.StreamsRunning)
                    done(true)
                } else if (res.status == 491) {
                    // Both sides changed the call at once: try again shortly (RFC 3261 says 2.1-4 s)
                    c.localHold = !held
                    main.postDelayed({ setHold(c, held, done) }, 2500)
                } else { undoHold(c, held); done(false) }
            }
        }
    }
    private fun undoHold(c: Call, held: Boolean) {
        c.localHold = !held; c.media?.setHold(!held)
        setState(c, if (!held) CallState.Paused else CallState.StreamsRunning)
        _notice.value = if (held) "Could not put the call on hold" else "Could not take the call off hold"
    }

    fun toggleHold() {
        val c = currentCall() ?: liveCalls().firstOrNull { it.localHold } ?: return
        if (c.localHold) {
            // Resume (also after an automatic hold whose other call Android never reported as over): take the audio back
            userHeld.remove(c); takeFocus(force = true); setHold(c, false)
        } else { userHeld.add(c); setHold(c, true) }
    }

    // ---- Ringing ----
    /** Stop the ringtone (or call-waiting beep) of the ringing call; it keeps ringing for the caller until answered,
     *  declined or the PBX moves on (voicemail). */
    fun silence() {
        if (ringingCall() == null) return
        stopQuietRing(); _silenced.value = true
        PhoneService.silenceIncoming(appContext)
    }
    fun isRinging() = started && ringingCall() != null && !_silenced.value

    private val main = Handler(Looper.getMainLooper())
    private var tone: ToneGenerator? = null
    private var ringtone: Ringtone? = null
    private var beepTick = 0
    private val beep = object : Runnable {
        override fun run() {
            if (ringingCall() == null || _silenced.value) { stopQuietRing(); return }
            // The other call ended while ours still rings: ring properly from now on (owner 2026-10-08)
            if (!PhoneService.otherAppInCall(appContext) && !hasActiveCall()) { ringNormally(); return }
            if (beepTick++ % 4 == 0) {   // every 4 s (the other call is checked every second)
                // The beep plays into the call audio, which another app's call (WhatsApp) may not let through, so a
                // double buzz goes with it (owner 2026-10-12: "I would not have known my extension was ringing").
                callWaitingBuzz()
                try {
                    if (tone == null) tone = ToneGenerator(AudioManager.STREAM_VOICE_CALL, 70)
                    tone?.startTone(ToneGenerator.TONE_SUP_CALL_WAITING, 500)
                } catch (e: RuntimeException) { /* no tone available: the buzz still tells the user */ }
            }
            main.postDelayed(this, 1000)
        }
    }

    /** The other call ended while ours still rings: the phone's ringtone and the normal notification. */
    private fun ringNormally() {
        main.removeCallbacks(beep); tone?.release(); tone = null
        PhoneService.ringAgain(appContext)
        startRingtone(); startVibrate()
    }
    /** The phone's own ringtone (the ringer volume and Silent/Vibrate apply), until answered, declined, silenced or the
     *  caller gives up. */
    private fun startRingtone() {
        if (ringtone != null) return
        try {
            val am = appContext.getSystemService(AudioManager::class.java)
            if (am?.ringerMode != AudioManager.RINGER_MODE_NORMAL) return
            val uri = RingtoneManager.getActualDefaultRingtoneUri(appContext, RingtoneManager.TYPE_RINGTONE) ?: return
            ringtone = RingtoneManager.getRingtone(appContext, uri)?.apply {
                audioAttributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) isLooping = true
                play()
            }
        } catch (e: RuntimeException) { /* no ringtone: the notification still shows the call */ }
    }
    /** Call-waiting beep instead of the ringtone while another call is up. */
    private fun quietRing() { main.removeCallbacks(beep); beepTick = 0; main.postDelayed(beep, 200) }
    private fun stopQuietRing() {
        main.removeCallbacks(beep)
        tone?.release(); tone = null
        ringtone?.stop(); ringtone = null
        stopVibrate()
    }

    /** Ringing tone in the earpiece while the other side rings, when the PBX sends no ringing audio of its own. */
    private var ringback: ToneGenerator? = null
    private fun startRingback() {
        if (ringback != null) return
        try { ringback = ToneGenerator(AudioManager.STREAM_VOICE_CALL, 60).apply { startTone(ToneGenerator.TONE_SUP_RINGTONE) } }
        catch (e: RuntimeException) { }
    }
    private fun stopRingback() { ringback?.let { it.stopTone(); it.release() }; ringback = null }

    /** Vibration while ringing (owner 2026-10-12: on Vibrate the phone stayed silent and still), like the phone's own
     *  dialler: Vibrate mode vibrates, Sound mode only with Android's "Vibrate for calls" on, Silent never. Stops with the
     *  ringing (stopQuietRing: answered, declined, Silence, answered on another phone, caller gave up). */
    private var vibrating = false
    private fun vibrator(): Vibrator? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) appContext.getSystemService(VibratorManager::class.java)?.defaultVibrator
        else @Suppress("DEPRECATION") appContext.getSystemService(Vibrator::class.java)
    private fun startVibrate() {
        if (vibrating) return
        try {
            val on = when (appContext.getSystemService(AudioManager::class.java)?.ringerMode) {
                AudioManager.RINGER_MODE_VIBRATE -> true
                AudioManager.RINGER_MODE_NORMAL -> Settings.System.getInt(appContext.contentResolver, "vibrate_when_ringing", 0) == 1
                else -> false
            }
            val v = vibrator()
            if (!on || v == null || !v.hasVibrator()) return
            val pattern = VibrationEffect.createWaveform(longArrayOf(0, 1000, 1000), 0)   // 1 s on, 1 s off, until stopped
            if (Build.VERSION.SDK_INT >= 33) v.vibrate(pattern, VibrationAttributes.createForUsage(VibrationAttributes.USAGE_RINGTONE))
            else @Suppress("DEPRECATION") v.vibrate(pattern, AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE).build())
            vibrating = true
        } catch (e: RuntimeException) { /* no vibration: the ringtone and notification still show the call */ }
    }
    /** Call waiting while another call is up: a short double buzz (the beep alone may not get through). Silent
     *  mode stays silent; Sound and Vibrate both buzz. */
    private fun callWaitingBuzz() {
        try {
            if (appContext.getSystemService(AudioManager::class.java)?.ringerMode == AudioManager.RINGER_MODE_SILENT) return
            val v = vibrator() ?: return
            if (!v.hasVibrator()) return
            val buzz = VibrationEffect.createWaveform(longArrayOf(0, 180, 140, 180), -1)
            if (Build.VERSION.SDK_INT >= 33) v.vibrate(buzz, VibrationAttributes.createForUsage(VibrationAttributes.USAGE_COMMUNICATION_REQUEST))
            else @Suppress("DEPRECATION") v.vibrate(buzz, AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_COMMUNICATION_REQUEST).build())
        } catch (e: RuntimeException) { }
    }
    private fun stopVibrate() {
        if (!vibrating) return
        vibrating = false
        try { vibrator()?.cancel() } catch (e: RuntimeException) { }
    }

    // ---- Audio route: earpiece / speaker / Bluetooth / wired headset ----
    private var routeChosen = false   // the first call of a session picked its route; later calls (consult, add) keep it

    private fun updateRoutes() { _routes.value = router.available() }

    /** Bluetooth or a headset connected/disconnected (e.g. the car's hands-free picks up the phone mid-call). */
    private fun onDevicesChanged() {
        val before = _routes.value.map { it.route }
        updateRoutes()
        if (liveCalls().isEmpty()) return
        val now = _routes.value.map { it.route }
        when {
            AudioRoute.Bluetooth in now && AudioRoute.Bluetooth !in before -> setAudioRoute(AudioRoute.Bluetooth)
            _route.value !in now -> setAudioRoute(defaultRoute())
        }
    }

    private fun defaultRoute(): AudioRoute {
        val have = _routes.value.map { it.route }
        return listOf(AudioRoute.Bluetooth, AudioRoute.Headset, AudioRoute.Earpiece).firstOrNull { it in have } ?: AudioRoute.Speaker
    }

    private fun applyRoute() {
        if (!started) return
        router.apply(_route.value)
        updateProximity()
    }

    // Phone at the ear: screen off and touch ignored, so the cheek cannot press Hang up, Hold or Add participant
    // (owner 2026-10-10). Only on the earpiece while a call is up or being dialled; on speaker, Bluetooth or a headset
    // the screen stays usable. Android's proximity wake lock switches the screen back on when the phone moves away.
    private var proximity: android.os.PowerManager.WakeLock? = null
    private fun updateProximity() {
        val want = started && _route.value == AudioRoute.Earpiece &&
            liveCalls().any { it.state != CallState.IncomingReceived }
        val lock = proximity ?: appContext.getSystemService(android.os.PowerManager::class.java)
            ?.takeIf { it.isWakeLockLevelSupported(android.os.PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK) }
            ?.newWakeLock(android.os.PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK, "n2it:proximity")
            ?.apply { setReferenceCounted(false) }
            ?.also { proximity = it } ?: return
        if (want && !lock.isHeld) lock.acquire(4 * 3600 * 1000L)   // safety cap; released when the call ends
        else if (!want && lock.isHeld) lock.release(android.os.PowerManager.RELEASE_FLAG_WAIT_FOR_NO_PROXIMITY)
    }

    // Background voices (owner 2026-10-08: on speaker, people talking a few paces away came through to the other side).
    // WebRTC's noise suppression; read when a call's audio starts, so a change applies to the next call.
    private val _hwAec = MutableStateFlow(false)
    /** Settings: the phone's own echo canceller instead of WebRTC's; applies from the next call. */
    val phoneEchoCanceller: StateFlow<Boolean> = _hwAec
    fun setPhoneEchoCanceller(on: Boolean) {
        _hwAec.value = on
        appContext.getSharedPreferences("n2it_echo", Context.MODE_PRIVATE).edit().putBoolean("hw_aec", on).apply()
    }

    fun setBackgroundFilter(on: Boolean) {
        _gate.value = on
        appContext.getSharedPreferences("n2it_echo", Context.MODE_PRIVATE).edit().putBoolean("gate", on).apply()
    }

    /** WebRTC's echo canceller tunes itself during each call: nothing to do (kept for the Settings screen). */
    fun tuneEcho() {}
    fun tuneEchoOnce() {}

    fun setAudioRoute(r: AudioRoute) {
        if (!started || _routes.value.none { it.route == r }) return
        _route.value = r; routeChosen = true
        applyRoute()
    }

    /*
     * Audio focus (owner 2026-10-08: on the HONOR a WhatsApp call taken during a softphone call was not noticed and both
     * were heard at once). WhatsApp and other calling apps do not always show up as calls in Android's call list
     * (TelecomManager), but every one of them takes the audio focus when its call starts. So the app holds the focus for
     * the length of its calls and treats losing it to another app as "another call started": PhoneService's watcher then
     * holds ours. Getting it back (the other call ended) resumes ours. Losses right after our own actions (the audio
     * starting) are ours, not another app's: the focus is simply taken back.
     */
    private var focusRequest: AudioFocusRequest? = null
    @Volatile var focusLost = false
        private set
    private var focusGraceUntil = 0L
    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS, AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                if (System.currentTimeMillis() < focusGraceUntil) main.postDelayed({ takeFocus(force = true) }, 500)
                else focusLost = true
            }
            AudioManager.AUDIOFOCUS_GAIN -> focusLost = false
        }
    }
    private fun takeFocus(force: Boolean = false) {
        if (!started || (focusRequest != null && !force)) return
        val am = appContext.getSystemService(AudioManager::class.java) ?: return
        focusRequest?.let { am.abandonAudioFocusRequest(it) }
        // TRANSIENT, as Android's own phone app: music / video apps (YouTube, Spotify, Apple Music, Samsung Music, TikTok)
        // pause for the call and carry on by themselves when it ends; with a permanent GAIN many stayed paused (2026-10-31)
        val r = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
            .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            .setOnAudioFocusChangeListener(focusListener, main)
            .setWillPauseWhenDucked(true)
            .build()
        focusGraceUntil = System.currentTimeMillis() + 3000
        if (am.requestAudioFocus(r) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) { focusRequest = r; focusLost = false }
        else { focusRequest = r; focusLost = true }   // refused: another call holds the audio right now
    }
    private fun releaseFocus() {
        focusRequest?.let { appContext.getSystemService(AudioManager::class.java)?.abandonAudioFocusRequest(it) }
        focusRequest = null; focusLost = false
    }

    /** Calls the user put on hold themselves; [onOtherAppCall] never resumes these. */
    private val userHeld = mutableSetOf<Call>()
    private var otherAppCall = false

    /**
     * Another app (GSM, WhatsApp, Teams…) started or ended a call while ours is up. That app takes the
     * microphone and speaker, so hold ours (the PBX plays hold music to the other side), and resume it when
     * the other call is over.
     */
    fun onOtherAppCall(active: Boolean) {
        if (!started || active == otherAppCall) return
        otherAppCall = active
        if (active) {
            liveCalls().filter { it.answered && !it.localHold }.forEach { setHold(it, true) }
        } else {
            focusGraceUntil = System.currentTimeMillis() + 3000
            liveCalls().filter { it.localHold && it !in userHeld }.forEach { setHold(it, false) }
            main.postDelayed({ if (liveCalls().isNotEmpty()) takeFocus(force = true) }, 1500)
        }
    }

    /** When the longest-running call connected (for the notification timer), or null with no call. */
    fun callStartedAt(): Long? = if (!started) null
        else liveCalls().filter { it.connectedAt > 0 }.minOfOrNull { it.connectedAt }

    // ---- Transfer ----
    /** Blind transfer: hand the current call to [number] and drop out once the PBX has taken it. */
    fun blindTransfer(number: String) {
        val c = currentCall() ?: liveCalls().firstOrNull { it.answered } ?: return
        val n = cleanNumber(number)
        if (n.isBlank()) { _notice.value = "Not a valid number"; return }
        refer(c, "<${if ('@' in n) "sip:$n" else "sip:$n@${ua.domain}"}>")
    }

    private fun refer(c: Call, referTo: String) {
        val d = c.dialog ?: return
        c.transferring = true
        val req = ua.inDialog(d, "REFER").add("Refer-To", referTo).add("Referred-By", "<${ua.aor}>")
        ua.request(req, onRetry = { d.localCseq = it.cseq }) { res ->
            if (res.status < 200) return@request
            if (res.status >= 300) { c.transferring = false; _notice.value = "Transfer refused (${res.status})"; return@request }
            // Accepted: the PBX reports progress in NOTIFYs; if none comes, drop out anyway after 10 s
            main.postDelayed({ if (c.transferring) hangupCall(c) }, 10_000L)
        }
    }

    /** Attended transfer, step 1: put the caller on hold and ring [number]. The second call is placed once the hold
     *  has gone through (dialling while the first call is still "Pausing" could leave it on hold with nothing ringing);
     *  if it cannot be placed the caller is taken off hold again and the screen says why. */
    fun consult(number: String) {
        val n = cleanNumber(number)
        if (n.isBlank()) { _notice.value = "Not a valid number"; return }
        val c = currentCall()
        if (c == null || c.localHold) { placeConsult(n, null); return }
        pendingConsult = n to c
        main.postDelayed(consultFallback, 3000)   // the hold never confirmed: dial anyway
        setHold(c, true) { consultHoldDone(c) }
    }
    private var pendingConsult: Pair<String, Call>? = null
    private val consultFallback = Runnable { pendingConsult?.let { (n, held) -> pendingConsult = null; placeConsult(n, held) } }
    /** The held call reached Paused (or ended). */
    private fun consultHoldDone(call: Call) {
        val (n, held) = pendingConsult ?: return
        if (held !== call) return
        pendingConsult = null; main.removeCallbacks(consultFallback)
        if (call.state in ended) return
        placeConsult(n, held)
    }
    private fun placeConsult(n: String, held: Call?) {
        if (call(n)) return
        _notice.value = "Could not call $n"
        if (held != null && held.localHold && held !in userHeld) setHold(held, false)
    }

    // ---- 3-way calls: a conference room on the PBX ----
    // N2IT's global "n2it-app-conference" dialplan (2026-10-31): *32 + 7 digits joins room <digits>@<company domain>; it
    // closes by itself once fewer than two people are left (FreeSWITCH "mintwo"): the host can leave two or more talking,
    // but nobody is left alone in it. Before: FusionPBX's *30 room, which stayed open after the host left. (Every tenant
    // has it). Merge = we join a new random room, then transfer each person into it (REFER); the PBX mixes the audio,
    // which phones mixing it themselves (Linphone did) could not do as well. Proven on n2it 2026-10-22 (room 9876543).
    private var confCall: Call? = null
    private var confRoom: String? = null
    private val confPeople = mutableListOf<Participant>()
    private val pendingMerge = mutableListOf<Call>()

    /** Add participant: in a conference, ring [number] with the room left as it is (holding it would play hold music
     *  to everyone; our microphone is only muted there) and move them in when they answer. Otherwise hold the call and
     *  ring [number] (a consult), then [merge]. */
    fun addParticipant(number: String) {
        val conf = confCall
        if (conf == null) { consult(number); return }
        val c = startCall(number) ?: run { _notice.value = "Could not call ${cleanNumber(number)}"; return }
        c.autoMerge = true
        conf.media?.setMuted(true)
        publish()
    }

    /** Merge calls: everyone who has answered joins one conference with us. */
    fun merge() {
        val answered = liveCalls().filter { it.answered && it !== confCall && !it.transferring }
        if (confCall != null) { moveIntoRoom(answered); return }
        if (answered.size < 2) { _notice.value = "Wait for them to answer, then merge"; return }
        val room = "*32" + (1..7).map { "0123456789"[java.security.SecureRandom().nextInt(10)] }.joinToString("")
        val c = startCall(room) ?: run { _notice.value = "Could not start the conference"; return }
        confRoom = room; confCall = c
        pendingMerge.clear(); pendingMerge.addAll(answered)
        publish()
    }

    private fun moveIntoRoom(list: List<Call>) {
        val room = confRoom ?: return
        list.filter { it.state !in ended && it.answered }.forEach { c ->
            confPeople.removeAll { it.id == c.callId }
            confPeople += Participant(c.callId, c.number, Participant.Status.Talking, c.name)
            refer(c, "<sip:$room@${ua.domain}>")
        }
        // Back to the room: unmute there, and off hold if a consult had put it on hold
        confCall?.let { conf -> conf.media?.setMuted(_muted.value); if (conf.localHold) { userHeld.remove(conf); setHold(conf, false) } }
        publish()
    }

    /** Attended transfer, step 2: connect the held caller to the consulted party (REFER with Replaces); the PBX joins
     *  them and drops us. */
    fun completeTransfer() {
        val held = liveCalls().firstOrNull { it.localHold } ?: return
        val other = liveCalls().firstOrNull { it !== held } ?: return
        val d = other.dialog
        if (!other.answered || d == null) { _notice.value = "Wait for them to answer, or use Transfer"; return }
        fun enc(s: String) = java.net.URLEncoder.encode(s, "UTF-8")
        val replaces = "${enc(d.callId)}%3Bto-tag%3D${enc(d.remoteTag)}%3Bfrom-tag%3D${enc(d.localTag)}"
        refer(held, "<${d.remoteUri}?Replaces=$replaces>")
        other.transferring = true   // the PBX ends this one too; drop it ourselves if it does not
        main.postDelayed({ if (other.state !in ended && other.transferring && held.state in ended) hangupCall(other) }, 10_000L)
    }

    // ---- Do Not Disturb (this app only, always with an end time of at most 2 weeks) ----
    const val MAX_DND_MS = 14L * 24 * 3600 * 1000
    private val _dndUntil = MutableStateFlow<Long?>(null)
    /** End of DND in epoch ms, or null when off. */
    val dndUntil: StateFlow<Long?> = _dndUntil
    private val dndTimer = android.os.Handler(android.os.Looper.getMainLooper())
    private val dndExpire = Runnable { checkDnd() }
    private fun dndPrefs() = appContext.getSharedPreferences("n2it_dnd", Context.MODE_PRIVATE)

    fun dndActive() = (_dndUntil.value ?: 0L) > System.currentTimeMillis()

    /** Turn DND on until [until] (capped at 2 weeks from now), or off with null or a time already past. */
    fun setDnd(until: Long?) {
        val now = System.currentTimeMillis()
        val u = until?.coerceAtMost(now + MAX_DND_MS)?.takeIf { it > now }
        dndPrefs().edit().putLong("until", u ?: 0L).apply()
        _dndUntil.value = u
        dndTimer.removeCallbacks(dndExpire)
        if (u != null) dndTimer.postDelayed(dndExpire, u - now)
    }

    /** Ends an expired DND. The timer pauses while the phone sleeps, so this also runs on resume and on each call. */
    fun checkDnd() { if (_dndUntil.value != null && !dndActive()) setDnd(null) }

    /** Re-read the audio devices, e.g. after the Bluetooth permission was granted. */
    fun reloadSoundDevices() { if (started) updateRoutes() }

    fun refresh() { if (started) ua.refreshNow() }
}
