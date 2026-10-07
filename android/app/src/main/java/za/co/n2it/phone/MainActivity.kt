package za.co.n2it.phone

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext

// N2IT brand colours (same as the PBX theme: blue #145ab6, navy #0f3d80), instead of the wallpaper's colours.
private val N2itLight = lightColorScheme(primary = Color(0xFF145AB6), onPrimary = Color.White,
    primaryContainer = Color(0xFFD6E4F8), onPrimaryContainer = Color(0xFF0F3D80),
    secondary = Color(0xFF0F3D80), secondaryContainer = Color(0xFFE3EBF7), onSecondaryContainer = Color(0xFF0B2F63))
private val N2itDark = darkColorScheme(primary = Color(0xFF8FB8EE), onPrimary = Color(0xFF0B2F63),
    primaryContainer = Color(0xFF0F3D80), onPrimaryContainer = Color(0xFFD6E4F8),
    secondary = Color(0xFFA9C4EA), secondaryContainer = Color(0xFF16345F), onSecondaryContainer = Color(0xFFE3EBF7))

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        SipManager.init(this)
        setContent {
            val ctx = LocalContext.current
            val dark = isSystemInDarkTheme()
            MaterialTheme(colorScheme = if (dark) N2itDark else N2itLight) {
                Surface {
                    var perms by remember { mutableStateOf(false) }
                    val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
                        perms = true
                        // The core started before the permission answer; without a reload it keeps a dead microphone.
                        SipManager.reloadSoundDevices()
                        // The foreground service needs the mic permission decision first.
                        if (Account.load(ctx).isConfigured) PhoneService.start(ctx)
                    }
                    LaunchedEffect(Unit) {
                        val list = mutableListOf(Manifest.permission.RECORD_AUDIO, Manifest.permission.READ_CONTACTS, Manifest.permission.READ_PHONE_STATE)
                        if (Build.VERSION.SDK_INT >= 33) list += Manifest.permission.POST_NOTIFICATIONS
                        if (Build.VERSION.SDK_INT >= 31) list += Manifest.permission.BLUETOOTH_CONNECT   // car kit / headset
                        ask.launch(list.toTypedArray())
                    }
                    App(onSignedIn = { PhoneService.start(ctx) }, onSignedOut = { PhoneService.stop(ctx) })
                }
            }
        }
    }

    override fun onResume() { super.onResume(); SipManager.refresh() }
}
