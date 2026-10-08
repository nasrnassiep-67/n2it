package za.co.n2it.phone

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.media.AudioManager
import android.os.IBinder
import android.telecom.TelecomManager
import androidx.core.app.NotificationCompat
import androidx.core.app.Person
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

/**
 * Foreground service that keeps the SIP registration alive while the app is in the background,
 * so incoming calls ring. (Test build: FCM push can replace this later to save battery.)
 */
class PhoneService : Service() {
    override fun onBind(i: Intent?): IBinder? = null

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var fgTypes = 0

    override fun onCreate() {
        super.onCreate()
        SipManager.init(this)
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CH_STATUS, "Phone status", NotificationManager.IMPORTANCE_LOW))
        nm.createNotificationChannel(NotificationChannel(CH_CALL, "Incoming calls", NotificationManager.IMPORTANCE_HIGH))
        // The status notification follows the call: "Ready to receive calls" when idle, the ongoing call otherwise.
        scope.launch { SipManager.call.collect { refreshNotification() } }
        scope.launch { SipManager.dndUntil.collect { refreshNotification() } }
        // While a call is up, watch for another app's call (GSM, WhatsApp…) and hold/resume ours around it.
        scope.launch {
            SipManager.call.map { it != null }.distinctUntilChanged().collectLatest { inCall ->
                if (!inCall) { SipManager.onOtherAppCall(false); return@collectLatest }
                while (isActive) { SipManager.onOtherAppCall(otherAppInCall()); delay(1000) }
            }
        }
    }

    override fun onDestroy() { scope.cancel(); super.onDestroy() }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_HANGUP) { SipManager.hangup(); return START_STICKY }
        if (intent?.action == ACTION_DND_OFF) { SipManager.setDnd(null); return START_STICKY }
        if (intent?.action == ACTION_DECLINE) { SipManager.decline(); return START_STICKY }
        if (intent?.action == ACTION_SILENCE) { SipManager.silence(); return START_STICKY }
        val inCall = intent?.action == ACTION_IN_CALL
        fgTypes = types(inCall)
        try {
            ServiceCompat.startForeground(this, ID_STATUS, buildNotification(), fgTypes)
        } catch (e: RuntimeException) {
            // Mic type refused (permission missing or app not in the foreground): keep ringing without it.
            fgTypes = types(false)
            ServiceCompat.startForeground(this, ID_STATUS, buildNotification(), fgTypes)
        }
        return START_STICKY
    }

    private fun otherAppInCall() = otherAppInCall(this)

    private fun refreshNotification() {
        val n = buildNotification()
        try {
            ServiceCompat.startForeground(this, ID_STATUS, n, fgTypes)
        } catch (e: RuntimeException) {
            getSystemService(NotificationManager::class.java).notify(ID_STATUS, n)
        }
    }

    /**
     * Ongoing call: a call-style notification (green chip in the status bar, timer, Hang up) that opens
     * the call screen, so a minimised call is always one tap away. Ringing calls have their own notification.
     */
    private fun buildNotification(): Notification {
        val call = SipManager.call.value
        val b = NotificationCompat.Builder(this, CH_STATUS)
            .setSmallIcon(R.drawable.ic_stat_n2it)
            .setContentIntent(open(this))
            .setOngoing(true)
        if (call == null || call.state == org.linphone.core.Call.State.IncomingReceived) {
            val until = SipManager.dndUntil.value
            if (until != null) {   // orange, with Turn off: DND must not be forgotten
                val text = "Please disable DND to receive calls. Until " +
                    java.text.SimpleDateFormat("EEE d MMM, HH:mm", java.util.Locale.getDefault()).format(java.util.Date(until))
                return b.setContentTitle("DND enabled").setContentText(text)
                    .setStyle(NotificationCompat.BigTextStyle().bigText(text))
                    .setColor(0xFFE65100.toInt()).setColorized(true)
                    .addAction(0, "Turn off", dndOff(this)).build()
            }
            return b.setContentTitle("N2IT Phone").setContentText("Ready to receive calls").build()
        }
        val who = if (call.conference) "Conference: ${call.number}" else call.number
        val status = when {
            call.conference -> "Conference · ${call.participants.size + 1} people"
            call.onHold -> "On hold"
            call.state == org.linphone.core.Call.State.StreamsRunning || call.state == org.linphone.core.Call.State.Connected -> "Ongoing call"
            else -> "Calling…"
        }
        b.setContentTitle(who).setContentText(status)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setStyle(NotificationCompat.CallStyle.forOngoingCall(Person.Builder().setName(who).build(), hangUp(this)))
        SipManager.callStartedAt()?.let { b.setWhen(it).setUsesChronometer(true).setShowWhen(true) }
        return b.build()
    }

    /**
     * phoneCall keeps the registration alive. During a call we add microphone: since Android 11 an app
     * that is not on screen only gets real microphone audio from a microphone-type service, otherwise
     * the mic delivers silence (the "no audio" bug). Added when a call starts, while the app is on screen.
     */
    private fun types(inCall: Boolean): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return 0
        var t = ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL
        val mic = checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        if (inCall && mic && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) t = t or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
        return t
    }

    companion object {
        const val CH_STATUS = "status"; const val CH_CALL = "call"
        const val ID_STATUS = 1; const val ID_CALL = 2
        private const val ACTION_IN_CALL = "za.co.n2it.phone.IN_CALL"
        private const val ACTION_IDLE = "za.co.n2it.phone.IDLE"
        private const val ACTION_HANGUP = "za.co.n2it.phone.HANGUP"
        private const val ACTION_DND_OFF = "za.co.n2it.phone.DND_OFF"
        private const val ACTION_DECLINE = "za.co.n2it.phone.DECLINE"
        private const val ACTION_SILENCE = "za.co.n2it.phone.SILENCE"
        const val ACTION_ANSWER = "za.co.n2it.phone.ANSWER"

        /** True while another app has a call (GSM, WhatsApp and other apps that use Android's call system). A ringing
         *  GSM call (audio mode RINGTONE) is skipped, so an ignored ring does not hold ours; our own calls are not
         *  Telecom calls, so they never count. */
        fun otherAppInCall(c: Context): Boolean {
            val am = c.getSystemService(AudioManager::class.java)
            if (am.mode == AudioManager.MODE_RINGTONE) return false
            // Our call lost the audio to another app's call (WhatsApp and others that are not in Android's call list)
            if (SipManager.focusLost) return true
            // No call of ours up yet (a call is ringing in): a GSM call (IN_CALL) or another app's internet call
            // (IN_COMMUNICATION) holds the phone's audio
            if (!SipManager.hasActiveCall() && (am.mode == AudioManager.MODE_IN_CALL || am.mode == AudioManager.MODE_IN_COMMUNICATION)) return true
            if (c.checkSelfPermission(android.Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED) return false
            return try {
                c.getSystemService(TelecomManager::class.java).isInCall
            } catch (e: SecurityException) { false }
        }

        private fun action(c: Context, code: Int, what: String) = PendingIntent.getService(
            c, code, Intent(c, PhoneService::class.java).setAction(what),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)

        /** Answer opens the app (Android only gives a call the microphone from the screen) and answers there. */
        private fun answerIntent(c: Context) = PendingIntent.getActivity(
            c, 3, Intent(c, MainActivity::class.java).setAction(ACTION_ANSWER).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        private var lastCaller = ""; private var lastBusy = false

        private fun dndOff(c: Context) = PendingIntent.getService(
            c, 2, Intent(c, PhoneService::class.java).setAction(ACTION_DND_OFF),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)

        private fun hangUp(c: Context) = PendingIntent.getService(
            c, 1, Intent(c, PhoneService::class.java).setAction(ACTION_HANGUP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)

        private fun open(c: Context) = PendingIntent.getActivity(
            c, 0, Intent(c, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)

        fun start(c: Context) = ContextCompat.startForegroundService(c, Intent(c, PhoneService::class.java))
        fun stop(c: Context) { c.stopService(Intent(c, PhoneService::class.java)) }

        /** Switch the running service between idle (phoneCall) and in-call (phoneCall + microphone). */
        fun setInCall(c: Context, inCall: Boolean) {
            try {
                c.startService(Intent(c, PhoneService::class.java).setAction(if (inCall) ACTION_IN_CALL else ACTION_IDLE))
            } catch (e: IllegalStateException) {
                // Service not running and app in the background: nothing to upgrade.
            }
        }

        /**
         * Ringing call: Android's incoming-call notification with Decline and Answer, plus Silence. While another app's
         * call is up ([busy]) it makes no sound of its own (the earpiece beeps instead) and says so.
         */
        fun notifyIncoming(c: Context, caller: String, busy: Boolean, silenced: Boolean = false) {
            lastCaller = caller; lastBusy = busy
            val nm = c.getSystemService(NotificationManager::class.java)
            val person = Person.Builder().setName(caller.ifBlank { "Unknown" }).setImportant(true).build()
            val b = NotificationCompat.Builder(c, CH_CALL)
                .setSmallIcon(R.drawable.ic_stat_n2it)
                .setContentTitle(caller)
                .setContentText(when { silenced -> "Incoming call · silenced"; busy -> "Incoming call · you're on another call"; else -> "Incoming call" })
                .setCategory(NotificationCompat.CATEGORY_CALL).setPriority(NotificationCompat.PRIORITY_HIGH)
                .setStyle(NotificationCompat.CallStyle.forIncomingCall(person, action(c, 4, ACTION_DECLINE), answerIntent(c)))
                .setContentIntent(open(c)).setOngoing(true).setOnlyAlertOnce(true).setTimeoutAfter(45_000)
            if (!silenced) b.addAction(0, "Silence", action(c, 5, ACTION_SILENCE))
            // Android requires a full-screen intent for a call-style notification; while the phone is in use (e.g. on
            // another call) it shows as a heads-up banner instead of taking over the screen. Over another call or once
            // silenced it makes no sound of its own.
            b.setFullScreenIntent(open(c), true)
            if (busy || silenced) b.setSilent(true)
            nm.notify(ID_CALL, b.build())
        }

        /** The other call ended while ours still rings: the normal incoming-call notification (full screen if locked). */
        fun ringAgain(c: Context) { if (lastCaller.isNotEmpty()) notifyIncoming(c, lastCaller, busy = false) }

        fun silenceIncoming(c: Context) { if (lastCaller.isNotEmpty()) notifyIncoming(c, lastCaller, lastBusy, silenced = true) }

        fun clearIncoming(c: Context) {
            c.getSystemService(NotificationManager::class.java).cancel(ID_CALL)
        }
    }
}
