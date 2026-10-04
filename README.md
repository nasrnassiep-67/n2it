# Here are your Instructions

## MVP status
Done: sign-in (multi-tenant), sign-out, SIP registration, outgoing/incoming calls via CallKit, mute/speaker/DTMF, persisted recents,
contacts, voicemail dial + MWI badge, VoIP push client + gateway, Keychain password storage.
Before a TestFlight build: compile against the Linphone SDK and fix API drift, add app icon, set `aps-environment` to production for Release,
implement `verifySip()` in the gateway, and have Nasr add the PBX `/notify` hook.

## iOS CI
`.github/workflows/ios.yml`: every push to the iOS code runs an unsigned compile check on a macOS runner (no Apple account needed).
For TestFlight, add these repo secrets (Settings > Secrets and variables > Actions): `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`,
`ASC_KEY_P8_BASE64` (`base64 -i AuthKey_XXXX.p8`, from App Store Connect > Users and Access > Integrations > App Store Connect API, role *App Manager*).
Create the app record `za.co.n2it.softphone` in App Store Connect first, then run the workflow manually with *testflight* ticked.
