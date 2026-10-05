# N2IT Phone for Windows and Linux

Electron + JsSIP. Registers over WSS (default port 7443) to `<code>.voip.n2it.co.za`, so FusionPBX needs WebRTC
enabled (WSS listener, valid TLS certificate, extensions allowing WebRTC/DTLS-SRTP). Credentials are encrypted with
Windows DPAPI. Not a push client: incoming calls ring only while the app is running (it stays in the tray/taskbar).

    npm install
    npm start          # run
    npm run dist       # NSIS installer in dist/ (CI builds it on every push; download from the run's Artifacts)
    npm run dist:linux # AppImage + .deb (CI builds both desktop installers; download from the run's Artifacts)

Settings screen: microphone and speaker, echo/noise/AGC, WSS port, voicemail number, STUN. Not done yet: voicemail MWI badge (JsSIP has no SUBSCRIBE), attended transfer, recents, contacts, tray/auto-start.
