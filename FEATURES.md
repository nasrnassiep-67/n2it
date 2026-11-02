# N2IT Phone: feature list

What each version of the app does today. Update this file with every release (version + one line per feature).
iOS is built by the Mac session (see IOS-MAC-HANDOVER.md); a ✗ there means "not matched on iOS yet" as far as the
voip-server session knows.

Current versions: **Android 0.3.9** (Google Play internal testing + download page), **Windows/desktop 0.2.13**,
**iOS 0.3.4** (main; TestFlight has 0.3.2), iOS 0.3.5 in PR #29. iOS column checked against the code by the Mac session 2026-11-02. Updated 2026-11-02 by the voip-server session for the Mac session: **every ✗ or ? in the
iOS column is for the Mac session to check against the iOS code and close** (✓ = a commit shows it on iOS).

| Feature | Android | Desktop | iOS |
|---|:-:|:-:|:-:|
| **Engine and connection** | | | |
| Own SIP client over WebSocket (wss://<company>.voip.n2it.co.za/wss, 443) + Google WebRTC audio (Opus/G.711, DTLS-SRTP); no Linphone (Android 0.3.0, iOS 0.3.0) | ✓ | ✓ (WSS) | ✓ |
| Answer is prepared while the call rings: no ~2 s silence after Answer; 0.5 s ICE quiet window (0.3.2) | ✓ | ? | ✓ |
| Never answer without ICE candidates (else fail with a reason); WebRTC errors shown (toast + Settings, Copy) (0.3.0) | ✓ | ? | ✓ (0.3.0; errors in Last call problem + Copy details) |
| **Sign-in and accounts** | | | |
| Sign in with company code (or a full server address with a dot, e.g. demo.pilot.n2it.co.za), extension and password | ✓ | ✓ | ✓ |
| Sign-in only opens after the PBX accepts the password; clear refusal messages; eye button on the password (0.2.14) | ✓ | ✓ (0.2.11) | ✓ (0.3.1) |
| Saved password refused later: back to sign-in, stop retrying (fail2ban bans the network after 6 failures) (0.3.3) | ✓ | ✓ | ✓ |
| Several saved accounts, one active at a time; switch / add / log out (0.1.9) | ✓ | ✓ | ✓ (0.2.2) |
| Release build not debuggable; tester tools (last call problem, error pop-ups, crash report) behind 7 taps on the version (0.3.2) | ✓ | – | ✓ (0.3.0) |
| No cloud backup / new-phone copy of the app's data (0.2.9) | ✓ | – | ✗ (passwords in Keychain without ThisDeviceOnly: copied by an encrypted backup) |
| **Calling** | | | |
| Make and receive calls, keypad, recents (all / missed) | ✓ | ✓ | ✓ |
| Recents: last 30 days (max 3,000 calls), saved per account across restarts (0.3.9) | ✓ | ✓ (0.2.13) | ✓ (0.3.4) |
| Caller's name: phone contact, else company book, else the PBX's caller ID name; number underneath; on cards, bar, notifications (0.2.9) | ✓ | ? | ✓ (0.2.2; PBX name first, then contacts; CallKit screen, conference cards 0.3.5) |
| Company address book (FusionPBX Contacts) + phone contacts, search and tap to dial | ✓ | company | ✓ (0.2.2) |
| Contacts show only numbers the company's PBX can dial (dial_patterns from the PBX) (0.3.2) | ✓ | ? | ✓ (0.3.0) |
| Hold, mute, keypad during a call (RFC 2833 digits) | ✓ | ✓ | ✓ (+ SIP INFO fallback, 0.3.2) |
| Blind and attended transfer | ✓ | ✓ | ✓ |
| Add participant / Transfer: pick from company and phone contacts, typed numbers cleaned (0.2.5) | ✓ | ✗ | ✗ (typed only, cleaned; no contact picker) |
| Add participant / Transfer: a line names who the number reaches ("Not in your contacts"), the button names them (0.2.13) | ✓ | ✗ | ✗ |
| 3-way / Merge: both calls join a PBX conference room `*32` + 7 random digits; the room closes when fewer than two are left (0.3.8) | ✓ | ✓ (0.2.12, hands over to *32 when the host leaves) | ✓ (0.3.3) |
| Conference screen: one card per person (name, number, status), drop one person | ✓ | ✓ | ✓ (0.3.5, PR #29) |
| Call waiting: second call beeps instead of ringing over the current call; also buzzes during WhatsApp/GSM/Teams calls (0.2.11) | ✓ | ✓ | CallKit |
| Auto hold while a GSM / WhatsApp / Teams call is up, resume after | ✓ | ✓ (mic in use) | CallKit |
| Voicemail: waiting badge, one-tap dial | ✓ | ✓ | ✓ |
| Do Not Disturb, app only, always timed (1 h to 2 weeks), orange banner (0.1.8) | ✓ | ✓ | ✓ (0.2.2) |
| **Audio** | | | |
| One audio button: phone / speaker / Bluetooth / headset, auto Bluetooth (car) | ✓ | mic + speaker panel | CallKit |
| Echo: WebRTC's software echo canceller by default; Settings "Use the phone's own echo canceller" (off) (0.3.0) | ✓ | browser AEC | Apple voice-processing unit always (no switch) |
| "Filter out background voices" Settings switch | ✓ | ✗ | ✓ (0.3.0) |
| Music / video apps pause while an outgoing call rings (0.3.6) and resume by themselves after the call (temporary audio focus, 0.3.7) | ✓ | – | CallKit (system pauses and resumes media) |
| **Phone behaviour** | | | |
| Screen off at the ear during calls (proximity sensor, earpiece only) (0.2.6) | ✓ | – | CallKit (system, earpiece only); owner to confirm on a call |
| Incoming calls vibrate like the phone's dialler (Vibrate mode, "Vibrate for calls", Silent never) (0.2.10) | ✓ | – | CallKit |
| Ongoing-call notification, minimise call and return bar | ✓ | tray | CallKit |
| Incoming call: full-screen / notification with Answer, Decline, Silence | ✓ | toast + pop-up | CallKit |
| Rings with the app closed | foreground service | tray + start with Windows | VoIP push (global on the PBX; Release = production APNs) |
| Battery optimisation exemption prompt | ✓ | – | – |
| tel: / callto: / sip: links open the app | – | ✓ (Windows) | ✗ (iOS sends tel: to the Phone app; sip: possible) |
| Dark mode | system | ✓ | system |
| **Distribution** | | | |
| Store | Google Play (internal testing 0.3.8+, target SDK 36, App Bundle) + APK on the download page | Microsoft Store (in certification) + installers | TestFlight; App Store (unlisted) prepared |

## History (newest first)
- Android 0.3.9 (2026-10-31): recents keep the last 30 days (max 3,000 calls) per account, saved across restarts (were in memory only). iOS 0.3.4 / Windows 0.2.13 same rule.
- Android 0.3.8 (2026-10-31): Merge uses `*32` rooms that close below two people (n2it-app-conference, every PBX) instead of FusionPBX's `*30`, which stayed open after the host left. iOS 0.3.3 same.
- Android 0.3.7 (2026-10-31): temporary audio focus for calls, so YouTube, Spotify and other music apps resume by themselves after the call. 0.3.6: focus taken when an outgoing call is placed, so media pause while it rings.
- Android 0.3.5 (2026-10-26): Google Play build: target SDK 36, release build type, CI builds APK + Play bundle (live on Play internal testing as 0.3.8).
- Android 0.3.4 (2026-10-26): 3-way calls through a PBX conference room (Merge joins both calls in it).
- Android 0.3.3 (2026-10-23): a saved password refused by the PBX sends the user back to sign-in and stops retrying (fail2ban).
- Android 0.3.2 (2026-10-22): release build for clients (not debuggable), tester tools behind 7 taps on the version; contacts show only numbers the PBX can dial; answer prepared while ringing (no 2 s silence).
- Android 0.3.0 / 0.3.1 (2026-10-22): Linphone SDK removed: own SIP-over-WebSocket client + Google WebRTC audio; WebRTC echo canceller by default with a Settings switch for the phone's own; 3-way via a conference room (0.3.1).
- Android 0.2.14 (2026-10-20): sign-in checks the extension and password with the PBX before saving; clear refusal messages.
- Android 0.2.13 (2026-10-19, branch `add-participant-pick`): Add participant / Transfer number box. Tapping a contact only copied
  its number into the box, so after typing a full extension (1002) the tap changed nothing and Add had to be pressed "again".
  Now a highlighted line under the box says who the number reaches (contact name + number, or "Not in your contacts"),
  the Add button names them ("Add Nasr", "Call Nasr" outside a conference), and a list that would only repeat the one
  matching contact is hidden. A typed number needs one press; a tapped contact is visibly chosen. Still two steps on purpose
  (pick, then press the button): one tap must not call or add the wrong person into a live conference.
- Desktop 0.2.9 (2026-10-13): Microsoft Store package (MSIX/AppX, identity N2ITSolutions.N2ITPhone, Store ID 9P1RH1TKPLDB),
  built unsigned by CI for Partner Center; in the Store build tel:/callto:/sip: come from the package manifest.
- Desktop 0.2.8 (2026-10-13): the in-call Add button (conference) did nothing, because Electron has no window.prompt();
  it now opens a small panel like Transfer's (number, Call, Cancel; Enter / Esc work).
- Android 0.2.12 / desktop 0.2.7 (2026-10-13): the company code box also takes a full server address (anything with a
  dot is used as typed, e.g. demo.pilot.n2it.co.za), for PBXs on other N2IT servers or a client's own server; a plain
  code still means <code>.voip.n2it.co.za. Desktop: WebSocket allowed to any wss: host (was *.voip.n2it.co.za only).
  iOS 0.2.4 (2026-10-13): same rule; push registers with the account's own server (https://<server>/push), tenant
  sent as typed (code or full address).
- Android 0.2.11 (2026-10-12): call waiting during another app's call (WhatsApp, GSM, Teams) also buzzes twice every
  4 s, not only the in-call beep, which WhatsApp's audio may not let through (Silent mode stays silent).
- Android 0.2.10 (2026-10-12): incoming calls vibrate like the phone's dialler (Vibrate mode always, Sound mode with
  "Vibrate for calls" on, Silent never); before, a phone on Vibrate gave no sign of a call apart from the screen.
- Desktop 0.2.6 (2026-10-12, security): no developer tools in the installed app, refuses to start with debug switches,
  Electron fuses off (run as Node, NODE_OPTIONS, --inspect; app only from its asar), so the saved password can't be read that way.
  Android 0.2.9 also: no cloud backup or new-phone copy of the app's data (users sign in again on a new phone).
- Android 0.2.9 (2026-10-12): calls show the caller's name: phone contact or company book, else the caller ID name
  the PBX sends ("Nasr" for 1002), number underneath; also on conference cards, the green bar and notifications.
- Android 0.2.7 (2026-10-10): strong echo limiter on speaker (Linphone speakerphone values), also applied to a
  conference mixed on the phone (3-way call on speaker: the others heard themselves).
- Android 0.2.6 (2026-10-10): screen off at the ear (proximity wake lock) while a call is on the earpiece.
- Android 0.2.5 (2026-10-10): Add participant / Transfer search company + phone contacts; numbers with spaces
  now ring (before, nothing rang and the first call stayed on hold); second call waits until the hold is done.
- Desktop 0.2.4 (2026-10-10): account switch de-registers the old account; keypad digits as RFC 2833.
- Android 0.2.4: Bluetooth static fix. 0.2.3: background voices filter. 0.2.2: audio focus auto-hold.
  0.2.1: call waiting + echo tuning. 0.2.0: outside calls fixed (SRTP optional), keep-alive.
- Desktop 0.2.3: Linux (AppImage, .deb, .pacman) start fix. 0.2.2: tray, start with Windows, new look, recents.
  0.2.1: ringing, Windows toast, call waiting, auto-hold, attended transfer. 0.2.0: microphone fallbacks.
