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
6. **Reviewer access** (App content > App access): the store test extension **1099 "Test Apple"** on company code
   `n2it` (the one Apple and Microsoft got; keep it enabled, password from the owner, never committed). Steps for the
   reviewer: enter company code, extension, password, Sign in; status shows Registered; dial 1000 (office phone) or
   *97 (voicemail). No account creation, purchases or ads.
7. **16 KB page size** (required by Play since 1 November 2025 for apps targeting Android 15+): checked on the 0.3.5 CI
   artifact (run 40308764098) with an ELF LOAD-segment scan: `libjingle_peerconnection_so.so` is 16 KB aligned for
   arm64-v8a and x86_64 (the ABIs Play checks); the 32-bit libs are 4 KB, which Play does not check. Re-check after any
   WebRTC upgrade.
8. **Graphics**: `/root/voip/n2it-app/store-android/` holds `play-icon-512.png` (512x512 PNG), `play-feature-1024x500.png`
   (feature graphic) and `appgallery-icon-216.png`, all made from `branding/N-2-Icon.png`. Screenshots are taken by the
   owner on a phone (Play: at least 2 portrait phone screenshots, 320 to 3840 px, PNG or JPEG; AppGallery: 3 to 5):
   sign-in, keypad, in-call, incoming call, company contacts.

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

## Developer accounts (what the owner does, in this order)
Both consoles verify the company, not a person, so the same three things are needed for both: the exact legal name and
address as registered with CIPC, the company registration number, and the D-U-N-S number.

### 0. D-U-N-S number (Google will not open an organisation account without it; Huawei accepts it instead of documents)
- Check first whether N2IT Solutions already has one: https://service.dnb.com/ (search by company name, South Africa).
- If not, request it free at https://www.dnb.com/duns/get-a-duns.html: legal name as on the CIPC certificate, registration
  number, physical address, phone, a contact person. Google says it can take up to 30 days; do not pay a third party for
  an "expedited" number. Google gives no extensions for accounts without one.

### Google Play Console (organisation account)
1. Google Account for the console: sign in with (or create a Google Account on) support@n2it.co.za, not a personal
   Gmail. That account becomes the Account Holder and only it can finish verification; moving a console later is painful.
2. https://play.google.com/console/signup: choose **Organisation**. Create a payments profile of type **Organisation**
   with the legal name and address exactly as on the D&B record (a mismatch error means: make a new payments profile).
   Pay the one-time US$25 with a Visa or Mastercard credit card (prepaid cards are refused; the fee is not refunded if
   verification fails).
3. Enter the D-U-N-S number and confirm the details Google shows from D&B.
4. Organisation contact: email support@n2it.co.za and a phone number (6-digit code by SMS or voice call). Both are shown
   publicly on the Play listing. Website: https://voip.n2it.co.za/download/.
5. Upload an ID document of an authorised representative (the owner's SA ID or passport).
6. Wait for the verification email (usually days, not weeks). Organisation accounts skip the personal-account rule of
   20 testers for 14 days, so the app can go to production straight after review.
7. Then: Create app (package `za.co.n2it.softphone`, Business, free), Play App Signing with our key, upload
   `n2it-phone.aab` to Internal testing, fill the listing and the declarations above, submit. Apps on Play are registered
   for Android developer verification automatically, which is what removes the Play Protect "unknown developer" warning
   for the download-page APK as well.

### Huawei AppGallery Connect (enterprise account)
1. https://developer.huawei.com/consumer/en/ > Register: a HUAWEI ID on support@n2it.co.za with the company phone number
   (verification codes go to both).
2. Console > Identity verification > **Enterprise**, country South Africa. Two paths; the D-U-N-S one is the easiest once
   the number exists. The business-licence path = the CIPC registration certificate (CoR 14.3): the enterprise name must
   be typed exactly as on it (case, punctuation, spaces, "(PTY) LTD"), plus the registration number and the English name.
   Contact person: name, phone, email; some countries also ask for the contact person's ID and a bank proof (bank letter
   or statement header), so have the owner's ID and a bank letter ready. No fee. Review is reported as 1 to 3 working
   days; rejections are almost always a name that does not match the document or a blurred scan.
3. After verification: AppGallery Connect > My apps > New > Android, package `za.co.n2it.softphone`, Business. Upload
   `n2it-phone.apk` from the `latest` release (keep AppGallery's own signing OFF, see above), same listing, privacy URL
   and reviewer extension 1099 as for Play. Payment and tax details are only needed for paid apps or in-app purchases.

### Listing text (both stores)
Short description (80 chars for Play): `Business softphone for your company's N2IT phone system: calls on your phone.`
Full description: the Windows one in `/root/voip/n2it-app/store-listing.md` with "PC" replaced by "phone", "Teams" by
"WhatsApp", and the "start with Windows / tray" line replaced by "Rings in the background with a foreground service".
Category Business; privacy https://voip.n2it.co.za/download/privacy.html; support support@n2it.co.za.
