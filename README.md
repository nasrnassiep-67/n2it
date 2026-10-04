# Here are your Instructions

## MVP status
Done: sign-in (multi-tenant), sign-out, SIP registration, outgoing/incoming calls via CallKit, mute/speaker/DTMF, persisted recents,
contacts, voicemail dial + MWI badge, VoIP push client + gateway, Keychain password storage.
Before a TestFlight build: compile against the Linphone SDK and fix API drift, add app icon, set `aps-environment` to production for Release,
implement `verifySip()` in the gateway, and have Nasr add the PBX `/notify` hook.
