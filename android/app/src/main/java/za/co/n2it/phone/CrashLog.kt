package za.co.n2it.phone

import android.content.Context
import java.io.File

/**
 * Test builds: when the app crashes, the error is saved and shown on the next start (with Copy), so a tester can send
 * it instead of "it crashed". Android's own crash handling still runs afterwards.
 */
object CrashLog {
    private var installed = false
    private fun file(c: Context) = File(c.filesDir, "last-crash.txt")

    fun install(c: Context) {
        if (installed) return
        installed = true
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { t, e ->
            try {
                file(c).writeText("N2IT Phone ${BuildConfig.VERSION_NAME} (Android ${android.os.Build.VERSION.RELEASE}, " +
                    "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL})\nThread: ${t.name}\n${e.stackTraceToString()}")
            } catch (_: Exception) {}
            previous?.uncaughtException(t, e)
        }
    }

    /** The saved crash report, once (it is deleted when read). */
    fun take(c: Context): String? {
        val f = file(c)
        if (!f.exists()) return null
        return try { f.readText().also { f.delete() } } catch (_: Exception) { null }
    }
}
