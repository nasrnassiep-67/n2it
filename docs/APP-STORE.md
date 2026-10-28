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
2. Request unlisted distribution: developer.apple.com/support/unlisted-app-distribution (App Apple ID 6821962053).
3. Fill in the App Store listing in App Store Connect (text below), upload the screenshots, answer App Privacy and
   the age rating, then add build 0.3.1 (202610241554) and Submit for Review.
4. After approval: the PBX session points the download page iPhone button at the App Store link.

## Availability

All countries **except China mainland** (Apple does not allow CallKit apps there; review rejects them otherwise).
Price: Free.

## Listing text

- **Name:** N2IT Phone (if taken, "N2IT Softphone", the current record name)
- **Subtitle (30):** Your N2IT business extension
- **Category:** Business (secondary: Productivity)
- **Promotional text:** Take your office extension anywhere: calls ring on your iPhone, even when it's locked.
- **Keywords (100):** softphone,voip,sip,pbx,business phone,extension,calls,office,n2it,voicemail
- **Support URL:** https://www.n2it.co.za/
- **Privacy Policy URL:** https://www.n2it.co.za/privacy/
- **Copyright:** 2026 N2IT

**Description:**

N2IT Phone puts your N2IT business phone extension on your iPhone. Make and receive company calls from anywhere,
with the same number, voicemail and colleagues you have at the office.

- Calls ring like normal iPhone calls, even when the phone is locked
- Company contacts and extensions from your PBX, alongside your own contacts
- Hold, mute, keypad, and switching between iPhone, speaker, Bluetooth and car kits
- Transfer calls (blind or after speaking first) and add people to a 3-way call
- Do Not Disturb with an end time, so you never forget to switch it off
- Voicemail indicator and one tap to listen
- Recents with caller names
- More than one extension on the same phone

N2IT Phone needs an extension on an N2IT phone system. Sign in with the company code, extension and password from
your N2IT administrator.

## App Review information

- **Sign-in required:** yes. Use the spare test extension given for TestFlight Beta Review (company code, extension,
  password). Put the company code in the notes, since the sign-in screen has three fields.
- **Notes:** "N2IT Phone is a business softphone for customers of N2IT's hosted phone system. To test: sign in with
  the details above, then dial 1002 (or *97 for voicemail). Incoming calls arrive by VoIP push and show the standard
  iOS call screen (CallKit). The app is distributed unlisted to N2IT's business customers."
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
