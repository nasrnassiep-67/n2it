# N2IT Phone (Android)

Kotlin + Jetpack Compose, WebRTC audio over a SIP WebSocket (no Linphone since 0.3.0). Same behaviour as the iOS app: multi-tenant sign-in (`<code>.voip.n2it.co.za`), keypad, recents, contacts,
voicemail dial + MWI badge, call screen with mute/speaker/DTMF, encrypted credential storage.

## Get a build
Merge to `main`: the **Android APK** workflow builds the release type and publishes the `latest` release with
`n2it-phone.apk` (download page, https://voip.n2it.co.za/download/) and `n2it-phone.aab` (upload to Google Play).
How versions are tagged and kept: `docs/ANDROID-RELEASES.md`.

## Build locally
JDK 17 + Android SDK 36, then `cd android && gradle assembleDebug` (output in `app/build/outputs/apk/debug/`).
Optional dev pre-fill: `gradle assembleDebug -PsipTenant=n2it -PsipUser=1002 -PsipPassword=...` (never commit these).

## Background calls
This test build keeps a foreground service running (persistent "Ready to receive calls" notification) so the SIP registration stays alive and
incoming calls ring with a full-screen notification. Some phones (Xiaomi, Samsung, Huawei) kill it unless battery optimisation is disabled for the app.
FCM push via the gateway is the production answer and is not built yet.
