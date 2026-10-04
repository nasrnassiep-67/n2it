# N2IT Phone (Expo mobile)

## Overview
Multi-tenant business softphone UI, modelled on the SwiftUI/Linphone reference app at
https://github.com/ebrahim-nassiep/n2it. Shipped as a React Native / Expo app with a
polished, dark-first, iOS-Phone-style interface. SIP/CallKit/PushKit are intentionally
mocked (platform limitation); the UI is 100% complete and ready for a native SIP module
to be dropped in later.

## Core features
- **Sign in**: company code + extension + password → derives server `<code>.voip.n2it.co.za`, persisted via AsyncStorage
- **Keypad**: large tactile 3x4 dialpad, typed number display, registration-status pill, haptics, settings icon, big green call button
- **Recents**: filter chips (All / Missed), direction icons, missed in red, timestamps + duration
- **Contacts**: sticky search, horizontal favorites row, alphabetical sections, tap-to-call
- **Voicemail**: list with unread dot, expand-to-play slider, call-back action, "Call voicemail" shortcut, tab badge
- **Settings** (modal): account info, SIP transport (UDP/TCP/TLS), port, SRTP toggle, voicemail number, push gateway host, sign-out
- **In-Call** (full-screen modal): dialing → connected states, running timer, 3x2 grid (Mute, Keypad, Speaker, Add call, Hold, Transfer), inline DTMF pad, red hangup
- **Incoming call** (full-screen): avatar, decline / accept actions, routes to in-call on accept

## Routes
- `/sign-in`, `/(tabs)` [index=Keypad, recents, contacts, voicemail], `/settings`, `/call/[number]`, `/incoming`

## Tech
- Expo Router, dark-first theme in `src/theme.ts`, Phosphor-style icons via `@react-native-vector-icons/material-design-icons`
- Haptics via `expo-haptics`, gradients via `expo-linear-gradient`, images via `expo-image`
- AsyncStorage-backed session + SIP settings (`src/store/session.ts`)

## NOT implemented (parity notes with native repo)
- **Real SIP / RTP** (Linphone SDK) — all call flows are MOCKED
- **CallKit / PushKit** background VoIP push — would need a native dev client
- Real contacts permission read; current contacts are seeded demo data
- Push gateway `/register` request — field is captured in settings but not posted

## Next action items
- Wrap with a native SIP module (e.g., `react-native-linphone`) and bridge to the UI
- Build the Node push gateway (`/notify`, `/register`) and wire PushKit via a dev client
- Replace mocked recents/voicemail with PBX / backend-driven data
