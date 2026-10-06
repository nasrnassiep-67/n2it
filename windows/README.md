# N2IT Phone for Windows, Linux and macOS

Electron + JsSIP. Registers over WSS to `wss://<code>.voip.n2it.co.za/wss` (port 443; nginx proxies it to FreeSWITCH's WSS on 7443), so FusionPBX needs WebRTC
enabled (WSS listener, valid TLS certificate, extensions allowing WebRTC/DTLS-SRTP). Credentials are encrypted with
Windows DPAPI. Not a push client: incoming calls ring only while the app is running (it stays in the tray/taskbar).

    npm install
    npm start          # run
    npm run dist       # NSIS installer in dist/ (CI builds it on every push; download from the run's Artifacts)
    npm run dist:linux # AppImage + .deb (CI builds both desktop installers; download from the run's Artifacts)
    npm run dist:mac   # .dmg + .zip, unsigned (build on a Mac; ad-hoc sign before running on Apple Silicon:
                       #   codesign --force --deep -s - "dist/mac-arm64/N2IT Phone.app")

Settings screen: microphone and speaker, echo/noise/AGC, WSS port, voicemail number, STUN. Not done yet: voicemail MWI badge (JsSIP has no SUBSCRIBE), attended transfer, recents, contacts, tray/auto-start.
