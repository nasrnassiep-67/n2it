// Runs after electron-builder lays out the app, before the installers/images are made.
// macOS: ad-hoc sign (adhoc-sign.js). Linux: put a small start script in front of the Electron binary, because
// Chromium reads these switches before our main.js runs:
//  - native Wayland when the desktop is Wayland (Omarchy/Hyprland, recent GNOME/KDE); X11 otherwise.
//  - Ubuntu 23.10+ blocks unprivileged user namespaces (AppArmor). Chromium then needs a setuid chrome-sandbox, which
//    an AppImage can't ship and the .deb install doesn't set (it tests namespaces as root, where they always work).
//    In that case only, run without Chromium's sandbox instead of crashing at start. Arch/Omarchy are unaffected.
const fs = require('fs')
const path = require('path')
const { execFileSync } = require('child_process')
const adhocSign = require('./adhoc-sign').default

// Security (owner 2026-10-12): Electron fuses off, so the saved extension password can't be reached by starting the
// app as plain Node (ELECTRON_RUN_AS_NODE), with NODE_OPTIONS or --inspect, or with a replaced app folder. Done with
// the pinned @electron/fuses CLI (electron-builder 25 has no electronFuses option; npm ci keeps the lockfile as is),
// BEFORE the macOS ad-hoc signature, which changing the binary would break. The build log prints the result.
const FUSES = ['RunAsNode=off', 'EnableNodeOptionsEnvironmentVariable=off', 'EnableNodeCliInspectArguments=off', 'OnlyLoadAppFromAsar=on']
function flipFuses (context) {
  const name = context.packager.appInfo.productFilename
  const app = { darwin: `${name}.app`, win32: `${name}.exe`, linux: context.packager.executableName }[context.electronPlatformName]
  const target = path.join(context.appOutDir, app)
  const win = process.platform === 'win32'   // npx.cmd needs the shell there, so quote the path ("N2IT Phone.exe")
  const run = (args) => execFileSync(win ? 'npx.cmd' : 'npx', ['--yes', '@electron/fuses@1.8.0', ...args, '--app', win ? `"${target}"` : target],
    { stdio: 'inherit', shell: win })
  run(['write', ...FUSES])
  run(['read'])
}

const wrapper = (bin) => `#!/bin/bash
HERE="$(dirname "$(readlink -f "$0")")"
ARGS=()
if [ -n "$WAYLAND_DISPLAY" ]; then ARGS+=(--ozone-platform-hint=auto --enable-wayland-ime); fi
if [ "$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns 2>/dev/null)" = "1" ] && [ ! -u "$HERE/chrome-sandbox" ]; then
  ARGS+=(--no-sandbox)
fi
exec "$HERE/${bin}" "\${ARGS[@]}" "$@"
`

exports.default = async (context) => {
  flipFuses(context)
  await adhocSign(context)
  if (context.electronPlatformName !== 'linux') return
  const name = context.packager.executableName
  const exe = path.join(context.appOutDir, name)
  fs.renameSync(exe, `${exe}.bin`)
  fs.writeFileSync(exe, wrapper(`${name}.bin`), { mode: 0o755 })
}
