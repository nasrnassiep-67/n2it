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
    override fun onNewToken(token: String) { PushToken.sync(this, token) }

    override fun onMessageReceived(message: RemoteMessage) {
        if (message.data["type"] != "call" || !Account.load(this).isConfigured) return
        SipManager.init(this)
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
