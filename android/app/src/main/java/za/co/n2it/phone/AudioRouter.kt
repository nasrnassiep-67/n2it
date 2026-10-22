package za.co.n2it.phone

import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper

/**
 * Where call audio goes (earpiece, loudspeaker, Bluetooth, wired headset), through Android's own call audio settings.
 * WebRTC records and plays in "voice communication" mode, so whatever Android routes calls to is what it uses.
 */
class AudioRouter(context: Context, private val onDevicesChanged: () -> Unit) {
    private val am = context.getSystemService(AudioManager::class.java)
    private val main = Handler(Looper.getMainLooper())
    private var inCall = false

    init {
        am.registerAudioDeviceCallback(object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(added: Array<out AudioDeviceInfo>) = onDevicesChanged()
            override fun onAudioDevicesRemoved(removed: Array<out AudioDeviceInfo>) = onDevicesChanged()
        }, main)
    }

    private fun routeOf(type: Int): AudioRoute? = when (type) {
        AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> AudioRoute.Earpiece
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> AudioRoute.Speaker
        // hands-free profile (car kits, headsets); A2DP is music-only
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> AudioRoute.Bluetooth
        AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_USB_HEADSET -> AudioRoute.Headset
        else -> if (Build.VERSION.SDK_INT >= 31 && type == AudioDeviceInfo.TYPE_BLE_HEADSET) AudioRoute.Bluetooth else null
    }

    private fun devices(): List<AudioDeviceInfo> =
        if (Build.VERSION.SDK_INT >= 31) am.availableCommunicationDevices
        else am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).toList()

    /** The routes this phone can use right now; [AudioOption.name] is the Bluetooth device's own name ("VW BT 1234"). */
    fun available(): List<AudioOption> {
        val found = devices().mapNotNull { d -> routeOf(d.type)?.let { it to d } }
        return AudioRoute.entries.mapNotNull { r ->
            found.firstOrNull { it.first == r }?.let { (_, d) -> AudioOption(r, if (r == AudioRoute.Bluetooth) d.productName?.toString() ?: "" else "") }
        }
    }

    /** A call starts: Android's call audio mode (WebRTC's echo canceller and the earpiece need it). */
    fun startCall() {
        if (inCall) return
        inCall = true
        am.mode = AudioManager.MODE_IN_COMMUNICATION
    }

    /** No call left: give the audio back to the phone. */
    fun endCall() {
        if (!inCall) return
        inCall = false
        if (Build.VERSION.SDK_INT >= 31) am.clearCommunicationDevice()
        else {
            @Suppress("DEPRECATION") run { if (am.isBluetoothScoOn) { am.stopBluetoothSco(); am.isBluetoothScoOn = false }; am.isSpeakerphoneOn = false }
        }
        am.mode = AudioManager.MODE_NORMAL
    }

    fun apply(route: AudioRoute) {
        if (!inCall) return
        if (Build.VERSION.SDK_INT >= 31) {
            val d = am.availableCommunicationDevices.firstOrNull { routeOf(it.type) == route } ?: return
            am.setCommunicationDevice(d)
            return
        }
        @Suppress("DEPRECATION") when (route) {
            AudioRoute.Bluetooth -> { am.isSpeakerphoneOn = false; am.startBluetoothSco(); am.isBluetoothScoOn = true }
            AudioRoute.Speaker -> { if (am.isBluetoothScoOn) { am.stopBluetoothSco(); am.isBluetoothScoOn = false }; am.isSpeakerphoneOn = true }
            else -> { if (am.isBluetoothScoOn) { am.stopBluetoothSco(); am.isBluetoothScoOn = false }; am.isSpeakerphoneOn = false }
        }
    }
}
