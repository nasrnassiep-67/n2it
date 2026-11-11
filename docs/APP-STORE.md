# iOS: App Store (unlisted)

Plan agreed 2026-10-28: the iPhone app moves from TestFlight to the App Store as an **unlisted** app. It goes
through normal App Review but never shows in search, charts or categories; it installs only from the direct link
`https://apps.apple.com/app/id6821962053`. Installs and updates work like any App Store app (no TestFlight, no 90-day
expiry, no Apple Account password prompt). TestFlight stays for beta builds.

Since 0.3.0 the app has no Linphone (own SIP over WSS + Google WebRTC, BSD), so there is no GPL issue.

## Owner steps (Apple account)

1. Optional, before going live: with the DUNS number, ask Apple Developer Support to convert the membership from
   individual to organisation so the store shows the company as seller instead of "Nasr Nassiep". Confirm with Apple
   that the team (8URJCQ48GM) and app record are kept.
2. Fill in the App Store listing in App Store Connect (text below), upload the screenshots, answer App Privacy and
   the age rating, add build 0.3.1 (202610241554). Under Version Release choose **Manually release this version**
   (so an approval before the unlisted request is granted can't go public), then Submit for Review. The review notes
   must say the app is intended for unlisted distribution (text below).
3. Only then request unlisted distribution: https://developer.apple.com/contact/request/unlisted-app/ (App Apple ID
   6821962053). Apple declines requests for apps not yet submitted to App Review, or in beta/prerelease.
4. Once granted, Pricing and Availability shows Distribution Method "Unlisted App"; release the approved version.
5. The PBX session points the download page iPhone button at the App Store link.

## Availability

All countries **except China mainland** (Apple does not allow CallKit apps there; review rejects them otherwise).
Price: Free.

## Listing text (Novamo; goes in with the launch version, nothing submitted yet)

The app is Novamo. N2IT stays the developer and publisher, and the description says "Powered by N2IT". The sign-in
screen does not. Do not change the App Store Connect name until the launch is called.

- **Name:** Novamo
- **Subtitle (30):** Your office phone, anywhere
- **Category:** Business (secondary: Productivity)
- **Promotional text:** Take your office extension anywhere: calls ring on your iPhone, even when it's locked.
- **Keywords (100):** softphone,voip,sip,pbx,business phone,extension,calls,office,voicemail,conference
- **Support URL:** https://www.n2it.co.za/
- **Privacy Policy URL:** https://www.n2it.co.za/privacy/
- **Copyright:** 2026 N2IT

**Description:**

Novamo puts your business phone extension on your iPhone. Make and receive company calls from anywhere, with the same
number, voicemail and colleagues you have at the office.

- Calls ring like normal iPhone calls, even when the phone is locked
- Company contacts and extensions from your phone system, alongside your own contacts
- Find people by name, extension or number when you add someone or transfer a call
- Conference calls that show who is in the call and who has left
- Hold, mute, keypad, and switching between iPhone, speaker, Bluetooth and car kits
- Transfer calls (blind or after speaking first)
- Do Not Disturb with an end time, so you never forget to switch it off
- Voicemail indicator and one tap to listen
- Recents with caller names
- More than one extension on the same phone

Novamo needs an extension on a compatible business phone system. Sign in with the company code, extension and password
from your administrator.

Powered by N2IT.

## App Review information

- **Sign-in required:** yes. Use the spare test extension given for TestFlight Beta Review (company code, extension,
  password). Put the company code in the notes, since the sign-in screen has three fields.
- **Notes:** keep the answers to the Guideline 2.1 questions already in the App Store Connect Notes field, change the
  app's name in them, and add this at the top: "Novamo is the new name of N2IT Softphone, approved as version 0.3.1. It
  is the same app and the same developer: N2IT renamed it so that business customers of its phone system resellers see
  a neutral name. Since 0.3.1 we added conference cards that show who is in a call, and a contact picker for adding
  people and transferring calls. To test: sign in with the details above, then dial 1002 (or *97 for voicemail).
  Incoming calls arrive by VoIP push and show the standard iOS call screen (CallKit). This app is intended for unlisted
  distribution to business customers."
- **Do not claim a licence** in the notes: N2IT has no current ICASA licence.
- Contact: owner's name, phone and email.

## App Privacy (nutrition label)

The app has no analytics, ads or tracking. Phone contacts are read on the device only, for names and dialling, and are
never uploaded. What leaves the phone goes to the company's own N2IT PBX and N2IT's push gateway:

| Data type | Why | Linked to user | Tracking |
|---|---|---|---|
| Identifiers > User ID (extension) | App Functionality | Yes | No |
| Identifiers > Device ID (push token, to ring locked phones) | App Functionality | Yes | No |
| User Content > Audio Data (calls; voicemail held on the PBX) | App Functionality | Yes | No |

Answer "No" to "Do you or your third-party partners use data for tracking?".

## Age rating

Answer "None" / "No" to every question → 4+. No unrestricted web access, no user-generated content shared publicly.

## Export compliance

Already answered by `ITSAppUsesNonExemptEncryption: false` in project.yml (standard encryption only: TLS, DTLS-SRTP).

## Screenshots

Required sizes: iPhone 6.9" (1320 × 2868) and iPad 13" (2064 × 2752), because the app also runs on iPad
(TARGETED_DEVICE_FAMILY 1,2).

Novamo set: `~/Desktop/Novamo-AppStore-Screenshots` (7 iPhone, 5 iPad). No Settings shot: it shows the server address,
which contains n2it. Conference shot: `-screenshotConference`; Add participant: `-screenshotCall -screenshotPicker 1002`.
Wait about 12 s after launch, because earlier shots of some tabs came out blank.

Debug builds have a screenshot mode with a demo extension and sample data that never contacts a PBX
(`N2IT/Screenshots.swift`). Simulators: iPhone 18 Pro Max and iPad Pro 13-inch.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project N2IT.xcodeproj -scheme N2IT -configuration Debug -destination 'id=<simulator>' -derivedDataPath dd build
xcrun simctl status_bar <simulator> override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3
xcrun simctl install <simulator> dd/Build/Products/Debug-iphonesimulator/N2IT.app
xcrun simctl launch --terminate-running-process <simulator> za.co.n2it.softphone -screenshots -screenshotTab 1   # 0 Contacts … 4 Settings
xcrun simctl launch --terminate-running-process <simulator> za.co.n2it.softphone -screenshots -screenshotCall    # call screen
xcrun simctl io <simulator> screenshot shot.png   # wait ~8 s after launch on a freshly booted iPad
```
