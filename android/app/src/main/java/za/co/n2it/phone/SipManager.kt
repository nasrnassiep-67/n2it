package za.co.n2it.phone

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.linphone.core.*
import org.linphone.core.Account as LpAccount

data class CallInfo(val number: String, val state: Call.State, val incoming: Boolean)
data class RecentCall(val number: String, val time: Long, val incoming: Boolean, val missed: Boolean)

object SipManager {
    private lateinit var core: Core
    private var started = false
    lateinit var appContext: Context; private set

    private val _registered = MutableStateFlow(false)
    private val _status = MutableStateFlow("Not registered")
    private val _call = MutableStateFlow<CallInfo?>(null)
    private val _muted = MutableStateFlow(false)
    private val _speaker = MutableStateFlow(false)
    private val _recents = MutableStateFlow<List<RecentCall>>(emptyList())
    private val _voicemail = MutableStateFlow(false)
    val registered: StateFlow<Boolean> = _registered
    val status: StateFlow<String> = _status
    val call: StateFlow<CallInfo?> = _call
    val muted: StateFlow<Boolean> = _muted
    val speaker: StateFlow<Boolean> = _speaker
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
                        val missed = incoming && call.callLog?.status == Call.Status.Missed
                        _recents.value = listOf(RecentCall(number, System.currentTimeMillis(), incoming, missed)) + _recents.value
                    }
                    _call.value = null; _muted.value = false; _speaker.value = false
                    PhoneService.clearIncoming(appContext)
                }
                Call.State.IncomingReceived -> {
                    _call.value = CallInfo(number, state, true)
                    PhoneService.notifyIncoming(appContext, number)
                }
                else -> _call.value = CallInfo(number, state, incoming)
            }
        }

        // PBX NOTIFY for message-summary: "Messages-Waiting: yes" / "Voice-Message: 2/0 (0/0)"
        override fun onNotifyReceived(core: Core, event: Event, notifiedEvent: String, body: Content?) {
            if (!notifiedEvent.equals("message-summary", true)) return
            val text = body?.utf8Text ?: return
            val waiting = Regex("Messages-Waiting:\\s*yes", RegexOption.IGNORE_CASE).containsMatchIn(text)
            val newCount = Regex("Voice-Message:\\s*(\\d+)/", RegexOption.IGNORE_CASE).find(text)?.groupValues?.get(1)?.toIntOrNull() ?: 0
            _voicemail.value = waiting || newCount > 0
        }
    }

    /** Safe to call repeatedly; the service and the activity both call it. */
    @Synchronized
    fun init(context: Context) {
        if (started) return
        appContext = context.applicationContext
        core = Factory.instance().createCore(null, null, appContext)
        core.addListener(listener)
        core.start()
        started = true
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
        params.isRegisterEnabled = true
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

    fun signOut(context: Context) {
        if (started) { core.clearAccounts(); core.clearAllAuthInfo() }
        za.co.n2it.phone.Account.clear(context)
        _registered.value = false; _status.value = "Not registered"; _recents.value = emptyList(); _voicemail.value = false
    }

    fun call(number: String) {
        if (!started || number.isBlank()) return
        val domain = core.defaultAccount?.params?.identityAddress?.domain ?: return
        core.invite(if ('@' in number) "sip:$number" else "sip:$number@$domain")
    }

    fun answer() { core.currentCall?.accept(); PhoneService.clearIncoming(appContext) }
    fun hangup() { core.currentCall?.terminate() }
    fun sendDigit(d: Char) { core.currentCall?.sendDtmf(d) }
    fun toggleMute() { core.isMicEnabled = !core.isMicEnabled; _muted.value = !core.isMicEnabled }
    fun toggleSpeaker() {
        val want = if (!_speaker.value) AudioDevice.Type.Speaker else AudioDevice.Type.Earpiece
        core.audioDevices.firstOrNull { it.type == want }?.let { core.outputAudioDevice = it; _speaker.value = !_speaker.value }
    }
    fun refresh() { if (started) core.refreshRegisters() }
}
