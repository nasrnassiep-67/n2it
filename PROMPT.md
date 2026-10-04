# Full build prompt: N2IT Phone (iOS)

Build a native iOS softphone called **N2IT Phone**, modelled on Acrobits Softphone, for the N2IT multi-tenant VoIP platform.

## Platform
- SwiftUI, iOS 16+, Xcode 15+. Project generated with XcodeGen (`project.yml`). Bundle id `za.co.n2it.softphone`.
- SIP/RTP via the Linphone SDK Swift package (`linphonesw`, https://gitlab.linphone.org/BC/public/linphone-sdk-swift-ios.git).

## Multi-tenancy
- Each client has a PBX at `<client>.voip.n2it.co.za` (e.g. client `n2it` -> `n2it.voip.n2it.co.za`).
- Sign-in screen asks for: company code, extension, password. Show the resolved hostname under the fields.
- SIP identity is `sip:<extension>@<client>.voip.n2it.co.za`. Defaults: UDP 5060; transport (UDP/TCP/TLS) and port editable in Settings.
- Dev credentials (tenant `n2it`, extension `1002`, password supplied by Nasr Nassiep) are pre-filled only through a gitignored `Config/Secrets.xcconfig`. Never hardcode credentials in source. Production builds leave them empty.

## Screens
1. **Sign in**: described above.
2. **Keypad**: 12-key dialer, green call button, backspace, registration status dot (green registered / red not).
3. **Recents**: incoming/outgoing/missed (red) calls with relative time; tap to call back.
4. **Call screen** (full-screen cover): caller number, state (Calling / Ringing / Incoming / Connected), mute, speaker, answer (incoming), hang up.
5. **Settings**: edit client, extension, password, port, transport; "Save & Register".
6. (Later) Contacts, voicemail, DTMF during call, BLF.

## Calls and background operation
- All calls go through **CallKit** (outgoing via `CXStartCallAction`, incoming via `reportNewIncomingCall`). Hand the audio session to Linphone in `didActivate` / `didDeactivate`.
- **PushKit VoIP push** for incoming calls while the app is closed or backgrounded:
  - Register a `PKPushRegistry`; upload the token plus tenant, extension and `sandbox` flag to `https://<PUSH_GATEWAY_HOST>/register`.
  - On every VoIP push, report a CallKit incoming call **immediately** (iOS terminates the app otherwise), then refresh SIP registration so the PBX can deliver the INVITE.
  - If the user answers before the INVITE arrives, remember it and accept when the INVITE shows up. Drop the placeholder call after 30 s if no INVITE comes.
  - Capabilities: Push Notifications, Background Modes (audio, voip), microphone usage description.
- Linphone's own push (flexisip) is disabled; we use our own gateway.

## Push gateway (Node 18, no dependencies, `gateway/server.js`)
- `POST /register` (app): verify SIP credentials against the tenant PBX, then store the device token under `tenant/extension`.
- `POST /unregister` (app): remove a token.
- `POST /notify` (PBX, `x-admin-key` header): `{tenant, user, caller}` -> send an APNs HTTP/2 VoIP push (topic `<bundle>.voip`, priority 10, ES256 JWT from the `.p8` key) to every device for that extension. Delete tokens APNs reports as invalid (410/400).
- Hosted at `push.voip.n2it.co.za` behind TLS.

## PBX requirements (Nasr)
1. On an incoming call to an extension, POST to the gateway `/notify`.
2. Keep ringing 20-30 s for extensions with no live registration, so the app can wake and register.
3. Confirm transport (UDP/TCP/TLS), port, and whether SRTP is required.
4. Confirm each client subdomain has DNS and a tenant on the PBX.

## Quality bar
- Credentials in Keychain for release builds. Registration status visible. Clear errors on failed registration.
- README with build steps, push flow, and an open-items list.
