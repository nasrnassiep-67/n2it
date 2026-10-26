# N2IT Phone (Android): Google Play and Huawei AppGallery

Package `za.co.n2it.softphone`. Builds: the `latest` release has `n2it-phone.apk` (download page, AppGallery) and
`n2it-phone.aab` (Google Play), both signed with the N2IT key (CI secret `N2IT_KEYSTORE_B64`). Every store must keep
that same key, or a store install and a download-page install cannot update each other (users would have to uninstall).
The key's SHA-256 is printed by the "Show signing certificate" step of every Android CI run:
`e47682a8a4863daa4fa0ab166e1e7893550e7ce94ab7c0d2f99985377f0bb2f6` (certificate `C=ZA, O=N2IT, CN=N2IT Phone`).

## Google Play (also removes the Play Protect warning)
1. **Play Console, organisation account** with the DUNS number. The company name and address must match the D&B record
   exactly. Organisation accounts skip the "20 testers for 14 days" rule of new personal accounts. The same account is
   the Android developer verification Google requires for apps installed outside Play (enforced country by country).
2. **Register the app**: package `za.co.n2it.softphone` and the N2IT key's SHA-256 (developer verification).
3. **Play App Signing**: choose to upload our existing key (Play Console offers an encrypted export with Google's PEPK
   tool), not a Google-generated one. The upload key can be the N2IT key at first; it can be changed later through Play
   support without changing what users install.
4. **Internal testing track**: upload `n2it-phone.aab`, add testers, install from the Play link. Then production.
5. **Store listing**: text from the Windows listing (`/root/voip/n2it-app/store-listing.md`, adjust "PC" to "phone"),
   privacy policy https://voip.n2it.co.za/download/privacy.html, support support@n2it.co.za, category Business.
6. **Reviewer access** (App content > App access): a test extension on a test PBX (n2test) with company code, extension
   and password, so the reviewer can sign in and call. Create a dedicated extension for this; do not reuse a real one.

### Declarations (App content), answers from what the code does
- **Foreground service** (`PhoneService`, types `phoneCall` + `microphone`): keeps the SIP registration up so calls
  ring, and holds the microphone during a call while the screen is off or the app is in the background. Video: incoming
  call ringing with the app closed, answer, talk with the screen locked.
- **Full-screen intent** (`USE_FULL_SCREEN_INTENT`): incoming-call screen on a locked phone. Calling apps are allowed.
- **Battery optimisation exemption** (`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`): VoIP app that must receive calls in the
  background; there is no push yet (FCM is planned, after which this can go).
- **Contacts** (`READ_CONTACTS`): names for numbers on the keypad, in recents and on incoming calls. Read on the phone
  only, never uploaded. The company directory is downloaded from the customer's own PBX.
- **Phone state** (`READ_PHONE_STATE`): only to see that a GSM call is in progress, so ours does not ring over it
  (`PhoneService.otherAppInCall`).
- **Microphone**, **Bluetooth connect**, **notifications**: calls, headsets/car kits, incoming-call alerts.

### Data safety (draft: owner to confirm)
Data goes only to the customer's N2IT PBX (operated by N2IT), never to third parties or ad/analytics services.
Encrypted in transit (TLS WebSocket, DTLS-SRTP audio). Deletion: on request to support@n2it.co.za, or the company
administrator removes the extension.
- Collected: **User IDs** (company code + extension, for sign-in); **Call logs** (numbers called and call times, kept
  by the PBX as call records); **Voice** (call audio, processed in real time, not stored by the app).
- Not collected: device contacts, location, device IDs, crash data (crashes are only shown on the phone).
- All of it is required for the app to work; none is shared.

## Huawei AppGallery (Huawei phones without Google services)
Huawei phones sold since 2019 have no Google Play, Play Protect or FCM. Honor phones (e.g. HONOR 90) do have Google
services and use the Play route. Global Huawei phones still run Android apps; HarmonyOS NEXT (China only) does not.
1. **AppGallery Connect, enterprise developer account**: Huawei asks for company registration documents and an
   authorised person (not DUNS). Verification takes a few working days.
2. **New app**, package `za.co.n2it.softphone`, upload `n2it-phone.apk`. Do **not** turn on AppGallery's app signing:
   keep our signature so download-page installs and AppGallery installs update each other.
3. Same listing, privacy policy and reviewer test extension as for Play.
4. Users without AppGallery installs get Huawei's "Pure mode" warning for apps from elsewhere; AppGallery avoids it.
5. Calls ring through the foreground service, which Huawei kills unless the user sets **Settings > Battery > App launch
   > N2IT Phone > Manage manually** (auto-launch, secondary launch, run in background all on). Put this in the user
   guide. Push on Huawei later needs HMS Push Kit (FCM does not work there).
