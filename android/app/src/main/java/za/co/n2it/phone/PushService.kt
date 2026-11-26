package za.co.n2it.phone

import android.content.Context
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * Firebase wake-up for incoming calls, the Android side of the iPhone push leg (PBX: n2it-app/push/ANDROID-PUSH.md).
 * The message only says "call" or "cancel" and nothing about the caller: the app registers, and the PBX then sends the
 * INVITE, which rings like any other call. "cancel" needs nothing here, because nothing is shown before the INVITE.
 * The background service stays as it is, for phones without Google services.
 */
class PushService : FirebaseMessagingService() {
    private val main = android.os.Handler(android.os.Looper.getMainLooper())

    override fun onNewToken(token: String) { PushToken.sync(this, token) }

    override fun onMessageReceived(message: RemoteMessage) {
        val type = message.data["type"]
        if (type == "cancel") { main.post { if (!SipManager.hasRingingCall()) PhoneService.clearPushRing(this) }; return }
        if (type != "call" || !Account.load(this).isConfigured) return
        SipManager.init(this)
        // 0.3.28: the "Incoming call" banner at once (PhoneService.notifyPushRing), unless the call already rings or one is
        // up (the app was awake and the INVITE came first), DND is on (the app turns the call away), or the push is late (the call is long gone). On the main
        // thread, where the call list lives.
        val fresh = message.sentTime <= 0 || System.currentTimeMillis() - message.sentTime < 30_000
        if (fresh) main.post { if (!SipManager.dndActive() && !SipManager.hasRingingCall() && !SipManager.hasActiveCall()) PhoneService.notifyPushRing(this) }
        // High-priority messages may start a foreground service; if Android refuses, registering can still ring us.
        try { PhoneService.start(this) } catch (e: IllegalStateException) { }
        SipManager.wake()
    }
}

/** Keeps the PBX's push gateway up to date with this phone's token (/push/register, checked with the SIP password). */
object PushToken {
    private fun prefs(c: Context) = c.getSharedPreferences("n2it_push", Context.MODE_PRIVATE)

    /** After each registration: sends the token if this account has not sent it yet. Quiet without Google services. */
    fun sync(c: Context) {
        val app = c.applicationContext
        try {
            FirebaseMessaging.getInstance().token.addOnSuccessListener { t -> if (!t.isNullOrEmpty()) sync(app, t) }
        } catch (e: Exception) { }
    }

    fun sync(c: Context, token: String) {
        val app = c.applicationContext
        Thread {
            val acc = Account.load(app)
            if (!acc.isConfigured) return@Thread
            val key = "${acc.user.trim()}@${acc.domain}|$token"
            if (prefs(app).getString("sent", null) == key) return@Thread
            val body = org.json.JSONObject().put("tenant", acc.domain).put("user", acc.user.trim()).put("password", acc.password)
                .put("token", token).put("platform", "android").put("bundle", app.packageName)
            if (post("https://${acc.domain}/push/register", body) == 200) prefs(app).edit().putString("sent", key).putString("token", token).apply()
        }.start()
    }

    /** Sign-out: this phone must not be woken for that extension any more. Runs before the account is cleared. */
    fun forget(c: Context) {
        val app = c.applicationContext
        val acc = Account.load(app)
        val token = prefs(app).getString("token", null) ?: return
        prefs(app).edit().clear().apply()
        Thread { post("https://${acc.domain}/push/unregister", org.json.JSONObject().put("tenant", acc.domain).put("user", acc.user.trim()).put("token", token)) }.start()
    }

    private fun post(url: String, body: org.json.JSONObject): Int = try {
        val conn = java.net.URL(url).openConnection() as java.net.HttpURLConnection
        conn.connectTimeout = 10_000; conn.readTimeout = 10_000
        conn.requestMethod = "POST"; conn.doOutput = true
        conn.setRequestProperty("Content-Type", "application/json")
        conn.outputStream.use { it.write(body.toString().toByteArray()) }
        try { conn.responseCode } finally { conn.disconnect() }
    } catch (e: Exception) { 0 }
}

/** A call that could not be made: its real SIP code goes to the PBX (/push/call-failed, checked with the SIP password),
 *  so support sees it in Call trace while the app only shows short words (Nathier 2026-11-26). Fire and forget. */
object CallFailReport {
    fun send(c: Context, code: Int, reason: String, shown: String, number: String, callId: String) {
        val app = c.applicationContext
        Thread {
            val acc = Account.load(app)
            if (!acc.isConfigured) return@Thread
            val body = org.json.JSONObject().put("tenant", acc.domain).put("user", acc.user.trim()).put("password", acc.password)
                .put("code", code).put("reason", reason).put("shown", shown).put("number", number).put("call_id", callId)
                .put("app", "Android ${BuildConfig.VERSION_NAME}").put("at", System.currentTimeMillis() / 1000)
            try {
                val conn = java.net.URL("https://${acc.domain}/push/call-failed").openConnection() as java.net.HttpURLConnection
                conn.connectTimeout = 10_000; conn.readTimeout = 10_000
                conn.requestMethod = "POST"; conn.doOutput = true
                conn.setRequestProperty("Content-Type", "application/json")
                conn.outputStream.use { it.write(body.toString().toByteArray()) }
                try { conn.responseCode } finally { conn.disconnect() }
            } catch (e: Exception) { }
        }.start()
    }
}
