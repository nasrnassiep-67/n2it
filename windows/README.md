# N2IT Phone for Windows

Electron + JsSIP. Registers over WSS (default port 7443) to `<code>.voip.n2it.co.za`, so FusionPBX needs WebRTC
enabled (WSS listener, valid TLS certificate, extensions allowing WebRTC/DTLS-SRTP). Credentials are encrypted with
Windows DPAPI. Not a push client: incoming calls ring only while the app is running (it stays in the tray/taskbar).

    npm install
    npm start          # run
    npm run dist       # NSIS installer in dist/ (run on Windows)

Not done yet: voicemail MWI badge (JsSIP has no SUBSCRIBE), attended transfer, recents, contacts, tray/auto-start.
