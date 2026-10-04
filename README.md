# N2IT Phone (iOS)

SwiftUI softphone modelled on Acrobits Softphone (keypad, recents, in-call controls, SIP account settings),
using the Linphone SDK for SIP/RTP. Multi-tenant: users sign in with a company code, a extension and a password; the app connects to `<code>.voip.n2it.co.za` (e.g. `n2it` -> `n2it.voip.n2it.co.za`).

## Build (needs a Mac with Xcode 15+)
1. `brew install xcodegen`
2. `Config/Secrets.xcconfig` optionally pre-fills a dev tenant/extension/password so you skip the sign-in screen (gitignored; template in `Secrets.example.xcconfig`). Leave values empty for production builds.
3. `xcodegen && open N2IT.xcodeproj`, set your signing team, run on a device (simulator has no mic).

## Not done yet
- **Incoming calls when backgrounded** need CallKit + PushKit and a SIP push gateway on the PBX. Right now calls ring only while the app is open.
- Contacts tab, voicemail/BLF, SRTP/TLS defaults: confirm with Nasr which transport/port the PBX expects (UDP 5060 is assumed; change in Settings).
- Credentials are seeded from Info.plist on first launch; move to Keychain before shipping to the App Store.

## Background calls (push)
Flow: PBX gets an INVITE for an extension -> PBX calls the gateway `/notify` -> gateway sends an APNs VoIP push ->
app wakes, reports a CallKit call immediately, re-registers SIP -> PBX delivers the INVITE -> user answers.

**App (done):** PushKit token registration, CallKit incoming/outgoing UI, audio-session handoff, token upload to
`https://$PUSH_GATEWAY_HOST/register`. Xcode needs the *Push Notifications* and *Background Modes (VoIP, Audio)* capabilities
on the target (XcodeGen writes the entitlement; the App ID must have Push Notifications enabled in the Apple developer portal).
Change `aps-environment` to `production` for release builds.

**Gateway (`gateway/server.js`):** `node server.js` with env `ADMIN_KEY`, `APNS_KEY_FILE` (.p8 from Apple, with the VoIP push topic `<bundle>.voip`),
`APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID`. Host it at `push.voip.n2it.co.za` behind TLS.

**Still needed from Nasr (PBX side):**
1. A hook on incoming calls that POSTs `{tenant,user,caller}` with `x-admin-key` to `/notify` (Asterisk dialplan `CURL()`/AGI, FreePBX, 3CX webhook...).
2. The PBX must keep the call ringing ~20-30s for an extension that has no live registration, so the app has time to wake and register.
3. Replace `verifySip()` in the gateway with a real credential check; right now anyone can register a token.

## Contacts and voicemail
- **Contacts:** reads the iPhone address book (Contacts permission), searchable; tap to call, with a number picker if a contact has several.
- **Voicemail:** the tab badge and counts come from SIP MWI (the PBX must send NOTIFY message-summary to the extension; the app subscribes automatically).
  "Call voicemail" dials the voicemail number from Settings (default `*97`, the Asterisk/FreePBX default; confirm with Nasr).
- **Not done:** a list of individual voicemail messages with playback needs a PBX API (e.g. FreePBX UCP / Asterisk ARI) or email-to-app delivery; ask Nasr what each tenant's PBX exposes.
