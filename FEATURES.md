# N2IT Phone: feature list

What each version of the app does today. Update this file with every release (version + one line per feature).
iOS is built by the Mac session (see IOS-MAC-HANDOVER.md); a ✗ there means "not matched on iOS yet" as far as the
voip-server session knows.

Current versions: **Android 0.2.12**, **desktop 0.2.8** (Windows, Mac, Linux), **iOS 0.2.4** (Ad Hoc from the Mac; TestFlight in review).

| Feature | Android | Desktop | iOS |
|---|:-:|:-:|:-:|
| **Sign-in and accounts** | | | |
| Sign in with company code, extension and password (TLS, SRTP when offered) | ✓ | ✓ (WSS) | ✓ |
| Several saved accounts, one active at a time; switch / add / log out (0.1.9) | ✓ | ✓ | ✗ |
| **Calling** | | | |
| Make and receive calls, keypad, recents (all / missed) | ✓ | ✓ | ✓ |
| Company address book (FusionPBX Contacts) + phone contacts, search and tap to dial | ✓ | company | phone |
| Hold, mute, keypad during a call (RFC 2833 digits) | ✓ | ✓ | ✓ |
| Blind and attended transfer | ✓ | ✓ | ✓ |
| Add participant + merge into a conference (mixed on the phone) | ✓ | ✓ | ✓ |
| Conference screen: one card per person (name, number, status), drop one person (0.2.8 / desktop 0.2.5) | ✓ | ✓ | ✗ |
| Add participant / Transfer: pick from company and phone contacts, typed numbers cleaned (0.2.5) | ✓ | ✗ | ✗ |
| Call waiting: second call beeps instead of ringing over the current call | ✓ | ✓ | CallKit |
| Auto hold while a GSM / WhatsApp / Teams call is up, resume after | ✓ | ✓ (mic in use) | CallKit |
| Voicemail: waiting badge, one-tap dial | ✓ | ✓ | ✓ |
| Do Not Disturb, app only, always timed (1 h to 2 weeks), orange banner (0.1.8) | ✓ | ✓ | ✗ |
| **Audio** | | | |
| One audio button: phone / speaker / Bluetooth / headset, auto Bluetooth (car) | ✓ | mic + speaker panel | CallKit |
| Echo cancellation tuned per phone, strong echo limiter on speaker, also in conferences (0.2.7) | ✓ | browser AEC | ✓ |
| Background voices filter (noise gate), Settings switch | ✓ | ✗ | ✗ |
| Bluetooth: own echo canceller off (no static with earbuds) | ✓ | – | ✗ |
| **Phone behaviour** | | | |
| Screen off at the ear during calls (proximity sensor, earpiece only) (0.2.6) | ✓ | – | check, see handover |
| Ongoing-call notification, minimise call and return bar | ✓ | tray | CallKit |
| Incoming call: full-screen / notification with Answer, Decline, Silence | ✓ | toast + pop-up | CallKit |
| Rings with the app closed | foreground service | tray + start with Windows | push (APNs key pending) |
| Battery optimisation exemption prompt | ✓ | – | – |
| tel: / callto: / sip: links open the app | – | ✓ (Windows) | ✗ |
| Dark mode | system | ✓ | system |

## History (newest first)
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
