// Runs after electron-builder lays out the app, before the installers/images are made.
// macOS: ad-hoc sign (adhoc-sign.js). Linux: put a small start script in front of the Electron binary, because
// Chromium reads these switches before our main.js runs:
//  - native Wayland when the desktop is Wayland (Omarchy/Hyprland, recent GNOME/KDE); X11 otherwise.
//  - AppImage on Ubuntu 23.10+ (AppArmor blocks unprivileged user namespaces, and an AppImage can't ship a setuid
//    chrome-sandbox): run without Chromium's sandbox instead of crashing at start. The .deb/.pacman keep the sandbox.
const fs = require('fs')
const path = require('path')
const adhocSign = require('./adhoc-sign').default

const wrapper = (bin) => `#!/bin/bash
HERE="$(dirname "$(readlink -f "$0")")"
ARGS=()
if [ -n "$WAYLAND_DISPLAY" ]; then ARGS+=(--ozone-platform-hint=auto --enable-wayland-ime); fi
if [ -n "$APPIMAGE" ] && [ "$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns 2>/dev/null)" = "1" ]; then
  ARGS+=(--no-sandbox)
fi
exec "$HERE/${bin}" "\${ARGS[@]}" "$@"
`

exports.default = async (context) => {
  await adhocSign(context)
  if (context.electronPlatformName !== 'linux') return
  const name = context.packager.executableName
  const exe = path.join(context.appOutDir, name)
  fs.renameSync(exe, `${exe}.bin`)
  fs.writeFileSync(exe, wrapper(`${name}.bin`), { mode: 0o755 })
}
