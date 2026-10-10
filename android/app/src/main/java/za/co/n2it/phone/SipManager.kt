package za.co.n2it.phone

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.media.ToneGenerator
import android.os.Handler
import android.os.Looper
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.linphone.core.*
import org.linphone.core.Account as LpAccount

data class CallInfo(val number: String, val state: Call.State, val incoming: Boolean, val onHold: Boolean = false, val consulting: Boolean = false,
                    val conference: Boolean = false, val participants: List<String> = emptyList())
data class RecentCall(val number: String, val time: Long, val incoming: Boolean, val missed: Boolean)

/** Where call audio goes: the phone's earpiece, the loudspeaker, a Bluetooth device (car kit, headset) or a wired headset. */
enum class AudioRoute { Earpiece, Speaker, Bluetooth, Headset }
/** A route the phone can use right now; [name] is the device's own name for Bluetooth ("VW BT 1234"). */
data class AudioOption(val route: AudioRoute, val name: String)

object SipManager {
    private lateinit var core: Core
    private var started = false
    lateinit var appContext: Context; private set

    private val _registered = MutableStateFlow(false)
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
    private val _echo = MutableStateFlow("")
    /** Echo tuning result for the Settings screen ("" = not tuned yet on this phone). */
    val echo: StateFlow<String> = _echo
    private val _gate = MutableStateFlow(true)
    /** "Filter out background voices" (Settings): Linphone's noise gate on the microphone. */
    val backgroundFilter: StateFlow<Boolean> = _gate
    val registered: StateFlow<Boolean> = _registered
    val status: StateFlow<String> = _status
    val call: StateFlow<CallInfo?> = _call
    val muted: StateFlow<Boolean> = _muted
    val audioRoute: StateFlow<AudioRoute> = _route
    val audioRoutes: StateFlow<List<AudioOption>> = _routes
    val recents: StateFlow<List<RecentCall>> = _recents
    val hasVoicemail: StateFlow<Boolean> = _voicemail

    private val listener = object : CoreListenerStub() {
        override fun onAccountRegistrationStateChanged(core: Core, account: LpAccount, state: RegistrationState, message: String) {
            _registered.value = state == RegistrationState.Ok
            if (state == RegistrationState.Ok) subscribeVoicemail()
            _status.value = when (state) {
                RegistrationState.Ok -> "Registered"
                RegistrationState.Progress -> "Registering…"
                RegistrationState.Failed -> "Failed: $message"
                else -> "Not registered"
            }
        }

        override fun onCallStateChanged(core: Core, call: Call, state: Call.State, message: String) {
            val number = call.remoteAddress.username ?: "Unknown"
            val incoming = call.dir == Call.Dir.Incoming
            when (state) {
                Call.State.End, Call.State.Error, Call.State.Released -> {
                    if (state != Call.State.Released) {
                        val missed = incoming && (call.callLog?.status == Call.Status.Missed || dndRefused.remove(call))
                        _recents.value = listOf(RecentCall(number, System.currentTimeMillis(), incoming, missed)) + _recents.value
                    }
                    PhoneService.clearIncoming(appContext)
                    if (core.calls.none { it !== call && it.state == Call.State.IncomingReceived }) stopQuietRing()
                    userHeld.remove(call)
                    consultHoldDone(call)
                    // Another call may still be up (held caller after a consult, or the rest of a conference).
                    if (liveCalls(except = call).isEmpty()) {
                        _call.value = null; _muted.value = false; routeChosen = false
                        releaseFocus(); updateProximity()
                        if (core.callsNb == 0) PhoneService.setInCall(appContext, false)
                    } else publish()
                }
                Call.State.IncomingReceived -> {
                    checkDnd()
                    if (dndActive()) {
                        // DND: refuse as busy; the PBX sends the caller to voicemail (or says there is none).
                        // Other phones on the same extension (e.g. a desk phone) keep ringing.
                        dndRefused.add(call)
                        call.decline(Reason.Busy)
                        return
                    }
                    // On a GSM / WhatsApp call: no ringtone over that call, a call-waiting beep in the earpiece instead
                    // (owner 2026-10-08). The notification still offers Answer, Decline and Silence.
                    val busy = PhoneService.otherAppInCall(appContext)
                    _silenced.value = false
                    _call.value = CallInfo(number, state, true)
                    PhoneService.notifyIncoming(appContext, number, busy)
                    if (busy) quietRing()
                }
                else -> {
                    if (state == Call.State.Paused) consultHoldDone(call)
                    if (state != Call.State.IncomingReceived && core.calls.none { it.state == Call.State.IncomingReceived }) stopQuietRing()
                    // Outgoing call placed, or incoming call answered: the user is in the app right now,
                    // so this is when Android lets the service take the microphone.
                    if (state == Call.State.OutgoingInit || state == Call.State.Connected) {
                        PhoneService.setInCall(appContext, true)
                        if (state == Call.State.Connected) takeFocus()
                        // First call: Bluetooth if connected (car, headset), else a wired headset, else the earpiece.
                        if (!routeChosen) { routeChosen = true; _route.value = defaultRoute() }
                        applyRoute()
                    }
                    // Streams restart after hold/resume and on answer: keep them on the chosen device.
                    if (state == Call.State.StreamsRunning) applyRoute()
                    publish()
                }
            }
        }

        // Echo tuning (owner 2026-10-08: callers heard themselves when this phone was on speaker). Linphone plays a few
        // beeps and measures how long this phone's speaker takes to reach its microphone, which its echo canceller needs;
        // without it the canceller guesses and on some phones (HONOR 90) lets the caller's voice back through.
        override fun onEcCalibrationResult(core: Core, status: EcCalibratorStatus, delayMs: Int) {
            val text = when (status) {
                EcCalibratorStatus.Done -> "Tuned for this phone (${delayMs} ms)"
                EcCalibratorStatus.DoneNoEcho -> "Tuned: this phone cancels echo itself"
                EcCalibratorStatus.Failed -> "Tuning failed: try again in a quiet room"
                else -> return
            }
            _echo.value = text
            appContext.getSharedPreferences("n2it_echo", Context.MODE_PRIVATE).edit().putString("result", text).apply()
        }

        // PBX NOTIFY for message-summary: "Messages-Waiting: yes" / "Voice-Message: 2/0 (0/0)"
        // Bluetooth or a headset connected/disconnected (e.g. the car's hands-free picks up the phone mid-call).
        override fun onAudioDevicesListUpdated(core: Core) {
            val before = _routes.value.map { it.route }
            updateRoutes()
            if (liveCalls().isEmpty()) return
            val now = _routes.value.map { it.route }
            when {
                AudioRoute.Bluetooth in now && AudioRoute.Bluetooth !in before -> setAudioRoute(AudioRoute.Bluetooth)
                _route.value !in now -> setAudioRoute(defaultRoute())
            }
        }

        override fun onNotifyReceived(core: Core, event: Event, notifiedEvent: String, body: Content?) {
            if (!notifiedEvent.equals("message-summary", true)) return
            val text = body?.utf8Text ?: return
            val waiting = Regex("Messages-Waiting:\\s*yes", RegexOption.IGNORE_CASE).containsMatchIn(text)
            val newCount = Regex("Voice-Message:\\s*(\\d+)/", RegexOption.IGNORE_CASE).find(text)?.groupValues?.get(1)?.toIntOrNull() ?: 0
            _voicemail.value = waiting || newCount > 0
        }
    }

    private val ended = setOf(Call.State.End, Call.State.Error, Call.State.Released)
    private fun liveCalls(except: Call? = null) = core.calls.filter { it !== except && it.state !in ended }
    /** A call of ours that is up (not just ringing in). */
    fun hasActiveCall() = started && liveCalls().any { it.state != Call.State.IncomingReceived }
    private fun conference(): Conference? = liveCalls().firstNotNullOfOrNull { it.conference }

    /** Mirror the calls into UI state: one call, a held call plus a consult call, or a conference. */
    private fun publish() {
        updateProximity()
        val calls = liveCalls()
        val conf = conference()
        if (conf != null) {
            val names = calls.filter { it.conference != null }.map { it.remoteAddress.username ?: "Unknown" }
            _call.value = CallInfo(names.joinToString(", "), Call.State.StreamsRunning, false,
                consulting = calls.any { it.conference == null }, conference = true, participants = names)
            return
        }
        val call = core.currentCall ?: calls.firstOrNull() ?: return
        val held = call.state == Call.State.Paused || call.state == Call.State.Pausing
        _call.value = CallInfo(call.remoteAddress.username ?: "Unknown", call.state, call.dir == Call.Dir.Incoming,
            held, calls.size > 1)
    }

    /** Safe to call repeatedly; the service and the activity both call it. */
    @Synchronized
    fun init(context: Context) {
        if (started) return
        appContext = context.applicationContext
        core = Factory.instance().createCore(null, null, appContext)
        core.addListener(listener)
        core.isEchoCancellationEnabled = true   // without AEC, speakerphone audio loops back into the mic
        _echo.value = context.applicationContext.getSharedPreferences("n2it_echo", Context.MODE_PRIVATE).getString("result", "") ?: ""
        _gate.value = context.applicationContext.getSharedPreferences("n2it_echo", Context.MODE_PRIVATE).getBoolean("gate", true)
        applyGate()
        // Shows on the PBX (registrations, logs) instead of "Unknown".
        core.setUserAgent("N2IT Phone Android", BuildConfig.VERSION_NAME)
        // STUN puts the phone's public address in the SDP, so the PBX can send audio before the phone does.
        core.natPolicy = core.createNatPolicy().apply {
            stunServer = "stun.l.google.com:19302"
            isStunEnabled = true
            isIceEnabled = false
        }
        core.start()
        started = true
        updateRoutes()
        setDnd(dndPrefs().getLong("until", 0).takeIf { it > 0 })   // survives restarts; clears itself if expired
        configure(Account.load(appContext))
    }

    fun configure(acc: za.co.n2it.phone.Account) {
        if (!started || !acc.isConfigured) return
        core.clearAccounts(); core.clearAllAuthInfo()
        val f = Factory.instance()
        val auth = f.createAuthInfo(acc.user, null, acc.password, null, null, acc.domain)
        val params = core.createAccountParams()
        params.identityAddress = f.createAddress("sip:${acc.user}@${acc.domain}")
        val server = f.createAddress("sip:${acc.domain}:${acc.port}")!!
        server.transport = when (acc.transport) { "TCP" -> TransportType.Tcp; "TLS" -> TransportType.Tls; else -> TransportType.Udp }
        params.serverAddress = server
        // SRTP preferred, never required: calls from the trunk reach the phone unencrypted, and a mandatory SRTP
        // answered them with 488 (outside callers never rang the app; internal calls arrive encrypted).
        core.mediaEncryption = if (acc.srtp) MediaEncryption.SRTP else MediaEncryption.None
        core.isMediaEncryptionMandatory = false
        params.isRegisterEnabled = true
        // Re-register every 10 min (default 1 h) and keep the connection alive: a mobile network drops an idle
        // connection after a few minutes, and the PBX can only reach the phone over a live one.
        params.expires = 600
        core.isKeepAliveEnabled = true
        val account = core.createAccount(params)
        core.addAuthInfo(auth); core.addAccount(account); core.defaultAccount = account
    }

    private var mwiSub: Event? = null

    /** Manual SUBSCRIBE for voicemail (message-waiting) notifications. */
    private fun subscribeVoicemail() {
        val addr = core.defaultAccount?.params?.identityAddress ?: return
        mwiSub?.terminate()
        mwiSub = core.createSubscribe(addr, "message-summary", 3600).also {
            it.addCustomHeader("Accept", "application/simple-message-summary")
            it.sendSubscribe(null)
        }
    }

    /** Another saved account becomes active: what was shown belongs to the previous one. */
    fun switchAccount(acc: za.co.n2it.phone.Account) {
        _recents.value = emptyList(); _voicemail.value = false; _registered.value = false; _status.value = "Registering…"
        configure(acc)
    }

    fun signOut(context: Context) {
        if (started) { core.clearAccounts(); core.clearAllAuthInfo() }
        za.co.n2it.phone.Account.clear(context)
        _registered.value = false; _status.value = "Not registered"; _recents.value = emptyList(); _voicemail.value = false
    }

    /** Rings [number]; false when it could not be dialled (not registered, or not a valid number). */
    fun call(number: String): Boolean {
        val n = cleanNumber(number)
        if (!started || n.isBlank()) return false
        val domain = core.defaultAccount?.params?.identityAddress?.domain ?: return false
        return core.invite(if ('@' in n) "sip:$n" else "sip:$n@$domain") != null
    }

    /** "082 123-4567", "(012) 345 6789" → digits; a typed SIP address (with @) is only trimmed. */
    fun cleanNumber(number: String) = number.trim().let { n -> if ('@' in n) n.filterNot { it.isWhitespace() } else n.filter { it in "+0123456789*#" } }

    private val _notice = MutableStateFlow<String?>(null)
    /** A short message for the call screen (e.g. the second call could not be placed); cleared by the screen. */
    val notice: StateFlow<String?> = _notice
    fun clearNotice() { _notice.value = null }

    fun answer() { (ringingCall() ?: core.currentCall)?.accept(); stopQuietRing(); PhoneService.clearIncoming(appContext) }
    private fun ringingCall() = core.calls.firstOrNull { it.state == Call.State.IncomingReceived }
    /** Decline the ringing call: the PBX carries on (other phones of the extension, voicemail). */
    fun decline() { ringingCall()?.decline(Reason.Declined); stopQuietRing(); PhoneService.clearIncoming(appContext) }

    /** Stop the ringtone (or call-waiting beep) of the ringing call; it keeps ringing for the caller until answered,
     *  declined or the PBX moves on (voicemail). */
    fun silence() {
        if (ringingCall() == null) return
        core.stopRinging(); stopQuietRing(); _silenced.value = true
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
            if (!PhoneService.otherAppInCall(appContext)) { ringNormally(); return }
            core.stopRinging()   // Linphone's ringtone, should it have started after us
            if (beepTick++ % 4 == 0) try {   // a beep every 4 s, the other call checked every second
                if (tone == null) tone = ToneGenerator(AudioManager.STREAM_VOICE_CALL, 70)
                tone?.startTone(ToneGenerator.TONE_SUP_CALL_WAITING, 500)
            } catch (e: RuntimeException) { /* no tone available: stay silent rather than ring */ }
            main.postDelayed(this, 1000)
        }
    }

    /** Linphone's own ringtone cannot be restarted once stopped: play the phone's ringtone until answered, declined,
     *  silenced or the caller gives up. */
    private fun ringNormally() {
        main.removeCallbacks(beep); tone?.release(); tone = null
        PhoneService.ringAgain(appContext)
        try {
            val uri = RingtoneManager.getActualDefaultRingtoneUri(appContext, RingtoneManager.TYPE_RINGTONE) ?: return
            ringtone = RingtoneManager.getRingtone(appContext, uri)?.apply {
                audioAttributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) isLooping = true
                play()
            }
        } catch (e: RuntimeException) { /* no ringtone: the notification still shows the call */ }
    }
    /** Call-waiting beep instead of the ringtone while another app's call is up. */
    private fun quietRing() { main.removeCallbacks(beep); beepTick = 0; core.stopRinging(); main.postDelayed(beep, 200) }
    private fun stopQuietRing() {
        main.removeCallbacks(beep)
        tone?.release(); tone = null
        ringtone?.stop(); ringtone = null
    }
    /** Ends the call in front of the user; in a conference with nobody else ringing, ends it for everyone. */
    fun hangup() {
        val c = core.currentCall
        if (c != null && c.conference == null) { c.terminate(); return }
        conference()?.terminate() ?: liveCalls().firstOrNull()?.terminate()
    }
    fun sendDigit(d: Char) { core.currentCall?.sendDtmf(d) }
    fun toggleMute() { core.isMicEnabled = !core.isMicEnabled; _muted.value = !core.isMicEnabled }

    // ---- Audio route: earpiece / speaker / Bluetooth / wired headset ----
    private var routeChosen = false   // the first call of a session picked its route; later calls (consult, add) keep it

    private fun routeOf(d: AudioDevice) = when (d.type) {
        AudioDevice.Type.Earpiece -> AudioRoute.Earpiece
        AudioDevice.Type.Speaker -> AudioRoute.Speaker
        AudioDevice.Type.Bluetooth -> AudioRoute.Bluetooth   // hands-free profile (car kits, headsets); A2DP is music-only
        AudioDevice.Type.Headset, AudioDevice.Type.Headphones -> AudioRoute.Headset
        else -> null
    }
    private fun player(r: AudioRoute) = core.audioDevices.firstOrNull { routeOf(it) == r && it.hasCapability(AudioDevice.Capabilities.CapabilityPlay) }
    /** Bluetooth and headsets use their own microphone when they have one; otherwise the phone's. */
    private fun recorder(r: AudioRoute): AudioDevice? {
        val mics = core.audioDevices.filter { it.hasCapability(AudioDevice.Capabilities.CapabilityRecord) }
        val own = if (r == AudioRoute.Bluetooth || r == AudioRoute.Headset) mics.firstOrNull { routeOf(it) == r } else null
        return own ?: mics.firstOrNull { it.type == AudioDevice.Type.Microphone }
    }

    private fun updateRoutes() {
        _routes.value = AudioRoute.entries.mapNotNull { r ->
            player(r)?.let { AudioOption(r, if (r == AudioRoute.Bluetooth) it.deviceName else "") }
        }
    }

    private fun defaultRoute(): AudioRoute {
        val have = _routes.value.map { it.route }
        return listOf(AudioRoute.Bluetooth, AudioRoute.Headset, AudioRoute.Earpiece).firstOrNull { it in have } ?: AudioRoute.Speaker
    }

    /** Point every live call (and a conference) at the chosen route, both ways: speaker and microphone. */
    private fun applyRoute() {
        if (!started) return
        val out = player(_route.value) ?: return
        val mic = recorder(_route.value)
        // A running call keeps its own devices; the core setting only applies to calls started afterwards.
        core.outputAudioDevice = out; mic?.let { core.inputAudioDevice = it }
        // On the loudspeaker also the echo limiter: it turns this phone's microphone down while the other side talks,
        // so their voice coming out of the speaker is not sent back to them (speakerphone works a little like a
        // walkie-talkie when both talk at once). Earpiece, headset and Bluetooth do not need it.
        val limiter = _route.value == AudioRoute.Speaker
        // Bluetooth earbuds and car kits cancel echo themselves; our canceller on top, tuned for this phone's own speaker
        // and not the Bluetooth delay, adds crackle (owner 2026-10-08: static on calls only with his earbuds).
        val ownAec = _route.value != AudioRoute.Bluetooth
        liveCalls().forEach { c -> c.outputAudioDevice = out; mic?.let { c.inputAudioDevice = it }; c.isEchoLimiterEnabled = limiter
            c.isEchoCancellationEnabled = ownAec }
        conference()?.let { c -> c.outputAudioDevice = out; mic?.let { c.inputAudioDevice = it } }
        updateProximity()
    }

    // Phone at the ear: screen off and touch ignored, so the cheek cannot press Hang up, Hold or Add participant
    // (owner 2026-10-10). Only on the earpiece while a call is up or being dialled; on speaker, Bluetooth or a headset
    // the screen stays usable. Android's proximity wake lock switches the screen back on when the phone moves away.
    private var proximity: android.os.PowerManager.WakeLock? = null
    private fun updateProximity() {
        val want = started && _route.value == AudioRoute.Earpiece &&
            liveCalls().any { it.state != Call.State.IncomingReceived }
        val lock = proximity ?: appContext.getSystemService(android.os.PowerManager::class.java)
            ?.takeIf { it.isWakeLockLevelSupported(android.os.PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK) }
            ?.newWakeLock(android.os.PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK, "n2it:proximity")
            ?.apply { setReferenceCounted(false) }
            ?.also { proximity = it } ?: return
        if (want && !lock.isHeld) lock.acquire(4 * 3600 * 1000L)   // safety cap; released when the call ends
        else if (!want && lock.isHeld) lock.release(android.os.PowerManager.RELEASE_FLAG_WAIT_FOR_NO_PROXIMITY)
    }

    // Background voices (owner 2026-10-08: on speaker, people talking a few paces away came through to the other side).
    // The noise gate turns the microphone down to 3% whenever the sound is quieter than someone speaking into the
    // phone, so the room only gets through while you talk. Read when a call's audio starts: a change applies to the
    // next call.
    private fun applyGate() {
        core.config.setInt("sound", "noisegate", if (_gate.value) 1 else 0)
        core.config.setFloat("sound", "ng_thres", 0.03f)
        core.config.setFloat("sound", "ng_floorgain", 0.03f)
        // Echo limiter strength for the loudspeaker (owner 2026-10-10: on speaker the other side still heard
        // themselves). Without these the limiter runs on mediastreamer's mild defaults and hardly turns the microphone
        // down. Values recommended by Linphone for speakerphone: while the other side's voice plays (el_thres), the
        // microphone drops hard (el_force) and stays down for 600 ms after they stop (el_sustain), so the tail of their
        // voice in the room is not sent back. Only used on calls with the limiter on, i.e. on Speaker (applyRoute).
        core.config.setString("sound", "el_type", "mic")
        core.config.setFloat("sound", "el_thres", 0.03f)
        core.config.setFloat("sound", "el_force", 100000f)
        core.config.setFloat("sound", "el_speed", 0.03f)
        core.config.setInt("sound", "el_sustain", 600)
        core.config.setFloat("sound", "el_transmit_thres", 1.7f)
    }
    fun setBackgroundFilter(on: Boolean) {
        _gate.value = on
        appContext.getSharedPreferences("n2it_echo", Context.MODE_PRIVATE).edit().putBoolean("gate", on).apply()
        if (started) applyGate()
    }

    /** Tune the echo canceller for this phone (a few seconds of beeps on the loudspeaker); not during a call. */
    fun tuneEcho() {
        if (!started || liveCalls().isNotEmpty()) return
        _echo.value = "Tuning… (keep the phone still and quiet)"
        if (core.startEchoCancellerCalibration() != 0) _echo.value = "Tuning failed: try again"
    }
    /** First start with the microphone allowed: tune once, so nobody has to know about it. */
    fun tuneEchoOnce() { if (_echo.value.isEmpty() || _echo.value.startsWith("Tuning…")) tuneEcho() }

    fun setAudioRoute(r: AudioRoute) {
        if (!started || player(r) == null) return
        _route.value = r; routeChosen = true
        applyRoute()
    }
    fun toggleHold() {
        val c = core.currentCall ?: core.calls.firstOrNull { it.state == Call.State.Paused } ?: return
        if (c.state == Call.State.Paused) {
            // Resume (also after an automatic hold whose other call Android never reported as over): take the audio back
            userHeld.remove(c); takeFocus(force = true); c.resume()
        } else { userHeld.add(c); c.pause() }
    }

    /*
     * Audio focus (owner 2026-10-08: on the HONOR a WhatsApp call taken during a softphone call was not noticed and both
     * were heard at once). WhatsApp and other calling apps do not always show up as calls in Android's call list
     * (TelecomManager), but every one of them takes the audio focus when its call starts. So the app holds the focus for
     * the length of its calls and treats losing it to another app as "another call started": PhoneService's watcher then
     * holds ours. Getting it back (the other call ended) resumes ours. Linphone may ask for the focus itself when a call
     * connects or resumes; losses right after our own actions are ours, not another app's: the focus is simply taken back.
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
        val r = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
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
     * the other call is over: resuming restarts the audio streams, which a running call would not get back.
     */
    fun onOtherAppCall(active: Boolean) {
        if (!started || active == otherAppCall) return
        otherAppCall = active
        val conf = conference()
        if (active) {
            if (conf != null) conf.leave()
            liveCalls().filter { it.conference == null && it.state == Call.State.StreamsRunning }.forEach { it.pause() }
        } else {
            focusGraceUntil = System.currentTimeMillis() + 3000   // Linphone may take the focus as the calls resume
            if (conf != null && !conf.isIn) conf.enter()
            liveCalls().filter { it.conference == null && it.state == Call.State.Paused && it !in userHeld }
                .forEach { it.resume() }
            main.postDelayed({ if (liveCalls().isNotEmpty()) takeFocus(force = true) }, 1500)
        }
    }

    /** When the longest-running call connected (for the notification timer), or null with no call. */
    fun callStartedAt(): Long? = if (!started) null
        else liveCalls().maxOfOrNull { it.duration }?.let { System.currentTimeMillis() - it * 1000L }

    /** Blind transfer: hand the current call to [number] and drop out. */
    fun blindTransfer(number: String) {
        val c = core.currentCall ?: core.calls.firstOrNull() ?: return
        val domain = core.defaultAccount?.params?.identityAddress?.domain ?: return
        val n = cleanNumber(number)
        val target = n.takeIf { it.isNotBlank() }?.let { Factory.instance().createAddress(if ('@' in it) "sip:$it" else "sip:$it@$domain") }
        if (target == null) { _notice.value = "Not a valid number"; return }
        c.transferTo(target)
    }

    /** Attended transfer, step 1: put the caller on hold and ring [number]. The second call is placed once the hold
     *  has gone through (dialling while the first call is still "Pausing" could leave it on hold with nothing ringing);
     *  if it cannot be placed the caller is taken off hold again and the screen says why. */
    fun consult(number: String) {
        val n = cleanNumber(number)
        if (n.isBlank()) { _notice.value = "Not a valid number"; return }
        val c = core.currentCall
        if (c == null || c.state == Call.State.Paused) { placeConsult(n, null); return }
        c.pause()
        pendingConsult = n to c
        main.postDelayed(consultFallback, 3000)   // the hold never confirmed: dial anyway
    }
    private var pendingConsult: Pair<String, Call>? = null
    private val consultFallback = Runnable { pendingConsult?.let { (n, held) -> pendingConsult = null; placeConsult(n, held) } }
    /** Called from onCallStateChanged: the held call reached Paused (or ended). */
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
        if (held != null && held.state == Call.State.Paused && held !in userHeld) held.resume()
    }

    /** Add participant, step 1: in a conference, invite [number] straight in; otherwise hold the call and ring
     *  [number] (same as a consult), then [merge] once they answer. */
    fun addParticipant(number: String) {
        val conf = conference()
        val domain = core.defaultAccount?.params?.identityAddress?.domain ?: return
        if (conf != null) {
            val n = cleanNumber(number)
            val target = n.takeIf { it.isNotBlank() }?.let { Factory.instance().createAddress(if ('@' in it) "sip:$it" else "sip:$it@$domain") }
            if (target == null) { _notice.value = "Not a valid number"; return }
            conf.addParticipant(target)
        } else consult(number)
    }

    /** Add participant, step 2: join every call into one conference, mixed on this phone (no PBX bridge needed). */
    fun merge() {
        val calls = liveCalls()
        if (calls.size < 2) return
        val conf = conference() ?: core.createConferenceWithParams(core.createConferenceParams(null).apply {
            isVideoEnabled = false
            isLocalParticipantEnabled = true
            subject = "N2IT conference"
        }) ?: return
        calls.filter { it.conference == null }.forEach { conf.addParticipant(it) }
    }

    /** Attended transfer, step 2: connect the held caller to the consulted party. */
    fun completeTransfer() {
        val calls = core.calls
        if (calls.size < 2) return
        val held = calls.firstOrNull { it.state == Call.State.Paused } ?: return
        val other = calls.firstOrNull { it !== held } ?: return
        held.transferToAnother(other)
    }

    // ---- Do Not Disturb (this app only, always with an end time of at most 2 weeks) ----
    const val MAX_DND_MS = 14L * 24 * 3600 * 1000
    private val _dndUntil = MutableStateFlow<Long?>(null)
    /** End of DND in epoch ms, or null when off. */
    val dndUntil: StateFlow<Long?> = _dndUntil
    private val dndRefused = mutableSetOf<Call>()
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

    /** Re-read the sound cards, e.g. after the microphone permission was granted (the core started without it). */
    fun reloadSoundDevices() { if (started) { core.reloadSoundDevices(); updateRoutes() } }

    fun refresh() { if (started) core.refreshRegisters() }
}
