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
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        SipManager.init(this)
        setContent {
            val ctx = LocalContext.current
            val dark = isSystemInDarkTheme()
            MaterialTheme(colorScheme = if (dark) dynamicDarkColorScheme(ctx) else dynamicLightColorScheme(ctx)) {
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
                        ask.launch(list.toTypedArray())
                    }
                    App(onSignedIn = { PhoneService.start(ctx) }, onSignedOut = { PhoneService.stop(ctx) })
                }
            }
        }
    }

    override fun onResume() { super.onResume(); SipManager.refresh() }
}
