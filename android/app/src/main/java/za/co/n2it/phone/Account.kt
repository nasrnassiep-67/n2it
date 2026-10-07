package za.co.n2it.phone

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

data class Account(
    val tenant: String = "",
    val user: String = "",
    val password: String = "",
    val port: Int = 5061,
    val transport: String = "TLS",
    val srtp: Boolean = true,
    val voicemail: String = "*97",
) {
    /** Each client has its own PBX at <tenant>.voip.n2it.co.za */
    val domain get() = if (tenant.isBlank()) "" else "${tenant.lowercase().trim()}.$BASE_DOMAIN"
    val isConfigured get() = tenant.isNotBlank() && user.isNotBlank() && password.isNotBlank()
    /** Same extension on the same PBX = same account. */
    fun sameAs(o: Account) = domain == o.domain && user.trim() == o.user.trim()

    companion object {
        const val BASE_DOMAIN = "voip.n2it.co.za"

        private fun prefs(c: Context) = EncryptedSharedPreferences.create(
            c, "account",
            MasterKey.Builder(c).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM)

        /** Saved account wins; dev defaults from gradle properties apply until the first sign-out. */
        fun load(c: Context): Account {
            val p = prefs(c)
            val dev = !p.getBoolean("signedOut", false)
            return Account(
                tenant = p.getString("tenant", null) ?: if (dev) BuildConfig.DEV_TENANT else "",
                user = p.getString("user", null) ?: if (dev) BuildConfig.DEV_USER else "",
                password = p.getString("password", null) ?: if (dev) BuildConfig.DEV_PASSWORD else "",
                port = p.getInt("port", 5061),
                transport = p.getString("transport", "TLS") ?: "TLS",
                srtp = p.getBoolean("srtp", true),
                voicemail = p.getString("voicemail", "*97") ?: "*97")
        }

        fun save(c: Context, a: Account) = prefs(c).edit()
            .putBoolean("signedOut", false)
            .putString("tenant", a.tenant.trim()).putString("user", a.user.trim()).putString("password", a.password)
            .putInt("port", a.port).putString("transport", a.transport).putBoolean("srtp", a.srtp).putString("voicemail", a.voicemail).apply()

        fun clear(c: Context) {
            val others = prefs(c).getString("others", null)
            prefs(c).edit().clear().putBoolean("signedOut", true).putString("others", others).apply()
        }

        // ---- More than one account (one active at a time) ----
        // The active account stays in the keys above; the others are kept as a JSON list under "others".

        private fun toJson(a: Account) = org.json.JSONObject().put("tenant", a.tenant).put("user", a.user)
            .put("password", a.password).put("port", a.port).put("transport", a.transport).put("srtp", a.srtp)
            .put("voicemail", a.voicemail)
        private fun fromJson(o: org.json.JSONObject) = Account(o.optString("tenant"), o.optString("user"),
            o.optString("password"), o.optInt("port", 5061), o.optString("transport", "TLS"), o.optBoolean("srtp", true),
            o.optString("voicemail", "*97"))

        /** Saved accounts that are not active. */
        fun others(c: Context): List<Account> {
            val arr = try { org.json.JSONArray(prefs(c).getString("others", "[]")) } catch (e: org.json.JSONException) { org.json.JSONArray() }
            return (0 until arr.length()).map { fromJson(arr.getJSONObject(it)) }.filter { it.isConfigured }
        }
        private fun saveOthers(c: Context, list: List<Account>) {
            val arr = org.json.JSONArray(); list.forEach { arr.put(toJson(it)) }
            prefs(c).edit().putString("others", arr.toString()).apply()
        }

        /** Make [a] the active account; the previous active one stays in the list. */
        fun activate(c: Context, a: Account) {
            val current = load(c)
            val rest = others(c).filterNot { it.sameAs(a) || (current.isConfigured && it.sameAs(current)) }
            saveOthers(c, (if (current.isConfigured && !current.sameAs(a)) listOf(current) else emptyList()) + rest)
            save(c, a)
        }

        /** Log [a] out and forget it. Returns the account that is active afterwards (null = none left). */
        fun remove(c: Context, a: Account): Account? {
            val current = load(c)
            if (!current.sameAs(a)) { saveOthers(c, others(c).filterNot { it.sameAs(a) }); return current.takeIf { it.isConfigured } }
            val next = others(c).firstOrNull()
            if (next == null) { clear(c); return null }
            saveOthers(c, others(c).drop(1)); save(c, next)
            return next
        }
    }
}
