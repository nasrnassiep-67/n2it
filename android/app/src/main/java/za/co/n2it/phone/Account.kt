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

        fun clear(c: Context) = prefs(c).edit().clear().putBoolean("signedOut", true).apply()
    }
}
