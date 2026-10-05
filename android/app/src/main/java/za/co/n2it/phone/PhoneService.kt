package za.co.n2it.phone

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * Foreground service that keeps the SIP registration alive while the app is in the background,
 * so incoming calls ring. (Test build: FCM push can replace this later to save battery.)
 */
class PhoneService : Service() {
    override fun onBind(i: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        SipManager.init(this)
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CH_STATUS, "Phone status", NotificationManager.IMPORTANCE_LOW))
        nm.createNotificationChannel(NotificationChannel(CH_CALL, "Incoming calls", NotificationManager.IMPORTANCE_HIGH))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val n = NotificationCompat.Builder(this, CH_STATUS)
            .setSmallIcon(android.R.drawable.sym_call_outgoing)
            .setContentTitle("N2IT Phone")
            .setContentText("Ready to receive calls")
            .setContentIntent(open(this))
            .setOngoing(true).build()
        val inCall = intent?.action == ACTION_IN_CALL
        try {
            ServiceCompat.startForeground(this, ID_STATUS, n, types(inCall))
        } catch (e: RuntimeException) {
            // Mic type refused (permission missing or app not in the foreground): keep ringing without it.
            ServiceCompat.startForeground(this, ID_STATUS, n, types(false))
        }
        return START_STICKY
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

        fun notifyIncoming(c: Context, caller: String) {
            val nm = c.getSystemService(NotificationManager::class.java)
            nm.notify(ID_CALL, NotificationCompat.Builder(c, CH_CALL)
                .setSmallIcon(android.R.drawable.sym_call_incoming)
                .setContentTitle("Incoming call").setContentText(caller)
                .setCategory(NotificationCompat.CATEGORY_CALL).setPriority(NotificationCompat.PRIORITY_HIGH)
                .setFullScreenIntent(open(c), true).setContentIntent(open(c))
                .setAutoCancel(true).setTimeoutAfter(45_000).build())
        }

        fun clearIncoming(c: Context) {
            c.getSystemService(NotificationManager::class.java).cancel(ID_CALL)
        }
    }
}
