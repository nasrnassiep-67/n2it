# N2IT Phone (Android)

Kotlin + Jetpack Compose, Linphone SDK. Same behaviour as the iOS app: multi-tenant sign-in (`<code>.voip.n2it.co.za`), keypad, recents, contacts,
voicemail dial + MWI badge, call screen with mute/speaker/DTMF, encrypted credential storage.

## Get a test APK
Push to GitHub: the **Android debug APK** workflow builds it and publishes it as a release. Stable link: https://github.com/ebrahim-nassiep/n2it/releases/download/latest/n2it-phone.apk
unzip, and install `app-debug.apk` on the phone (allow "install unknown apps").

## Build locally
JDK 17 + Android SDK 34, then `cd android && gradle assembleDebug` (output in `app/build/outputs/apk/debug/`).
Optional dev pre-fill: `gradle assembleDebug -PsipTenant=n2it -PsipUser=1002 -PsipPassword=...` (never commit these).

## Background calls
This test build keeps a foreground service running (persistent "Ready to receive calls" notification) so the SIP registration stays alive and
incoming calls ring with a full-screen notification. Some phones (Xiaomi, Samsung, Huawei) kill it unless battery optimisation is disabled for the app.
FCM push via the gateway is the production answer and is not built yet.
