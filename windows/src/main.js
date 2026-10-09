const { app, BrowserWindow, dialog, ipcMain, Menu, nativeImage, Notification, safeStorage, screen, session, shell, Tray } = require('electron')
const { execFile } = require('child_process')
const fs = require('fs')
const path = require('path')

// ---- Phone links: tel:, callto: and sip: (a number clicked in a browser, email or CRM) ----
// The app opens (or comes to the front) with the number in the dial box, ready to press Call.
const SCHEMES = ['tel', 'callto', 'sip']
const linkIn = (argv) => argv.find((a) => SCHEMES.some((s) => a.toLowerCase().startsWith(`${s}:`)))
/** "tel:+27%2021-555 1234" -> "+27215551234"; "sip:1002@n2it.voip.n2it.co.za" -> "1002". */
function numberOf(link) {
  let n = link.replace(/^[a-z]+:(\/\/)?/i, '')
  try { n = decodeURIComponent(n) } catch {}
  n = n.split(/[;?]/)[0].split('@')[0]
  return n.replace(/[^+0-9*#]/g, '')
}
let win = null, pendingDial = null
function dial(link) {
  const n = link && numberOf(link)
  if (!n) return
  if (win && !win.webContents.isLoading()) win.webContents.send('dial', n)
  else pendingDial = n
  showWindow()
}
// One window only: a link clicked while the app runs comes here instead of starting a second copy.
const primary = app.requestSingleInstanceLock()
if (!primary) app.quit()
// Buttons on the incoming-call notification come back as n2itphone:answer / :decline / :silence / :open
const actionIn = (argv) => argv.find((a) => /^n2itphone:/i.test(a))
app.on('second-instance', (_e, argv) => {
  const act = actionIn(argv)
  if (act) {
    const what = act.replace(/^n2itphone:(\/\/)?/i, '').replace(/\/$/, '').toLowerCase()
    win?.webContents.send('call:action', what)
    if (what === 'answer' || what === 'open') showWindow()
    return
  }
  const l = linkIn(argv)
  if (l) dial(l); else showWindow()   // started again from the Start menu: bring up the running one
})
app.on('open-url', (e, url) => { e.preventDefault(); dial(url) })   // macOS
pendingDial = linkIn(process.argv) ? numberOf(linkIn(process.argv)) : null

/**
 * Windows: list N2IT Phone under Settings > Apps > Default apps for tel/callto/sip (per user, no admin rights), and
 * take a scheme straight away when no other app handles it. Windows never lets an app take over a scheme another
 * app owns (e.g. Phone Link for tel:); the user picks N2IT Phone once there (Settings > "Phone links" button).
 */
function registerLinksWindows() {
  if (process.platform !== 'win32' || !app.isPackaged) return
  const exe = process.execPath, cls = 'HKCU\\Software\\Classes\\N2ITPhone.URL', caps = 'HKCU\\Software\\N2IT\\N2ITPhone\\Capabilities'
  const reg = (key, name, data) => new Promise((ok) =>
    execFile('reg', ['add', key, ...(name === null ? ['/ve'] : ['/v', name]), '/d', data, '/f'], () => ok()))
  Promise.all([
    reg(cls, null, 'N2IT Phone call'), reg(cls, 'URL Protocol', ''),
    reg(`${cls}\\DefaultIcon`, null, `"${exe}",0`), reg(`${cls}\\shell\\open\\command`, null, `"${exe}" "%1"`),
    reg(caps, 'ApplicationName', 'N2IT Phone'), reg(caps, 'ApplicationDescription', 'N2IT Phone softphone'),
    ...SCHEMES.map((s) => reg(`${caps}\\URLAssociations`, s, 'N2ITPhone.URL')),
    reg('HKCU\\Software\\RegisteredApplications', 'N2IT Phone', 'Software\\N2IT\\N2ITPhone\\Capabilities'),
  ]).then(() => {
    for (const s of SCHEMES) if (!app.getApplicationNameForProtocol(`${s}:`)) app.setAsDefaultProtocolClient(s)
    app.setAsDefaultProtocolClient('n2itphone')   // our own: the incoming-call notification's buttons
  })
}

// ---- Incoming calls (owner 2026-10-08: calls were only shown in the window, with no sound or pop-up) ----
// The page rings (WebAudio); here: bring the window up (unless another call is going on: then only flash it) and a
// Windows call notification with Answer / Decline / Silence that stays until the call is answered or ends.
let ringNote = null
const xml = (t) => String(t).replace(/[<>&'"]/g, (c) => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', "'": '&apos;', '"': '&quot;' }[c]))
function callToast(number, busy, silenced) {
  const line = silenced ? 'Incoming call · silenced' : busy ? 'Incoming call · you are on another call' : 'Incoming call'
  return `<toast launch="n2itphone:open" activationType="protocol" scenario="incomingCall"><visual><binding template="ToastGeneric">`
    + `<text>${xml(number)}</text><text>${xml(line)}</text></binding></visual><audio silent="true"/><actions>`
    + `<action content="Answer" arguments="n2itphone:answer" activationType="protocol"/>`
    + `<action content="Decline" arguments="n2itphone:decline" activationType="protocol"/>`
    + (silenced ? '' : `<action content="Silence" arguments="n2itphone:silence" activationType="protocol"/>`)
    + `</actions></toast>`
}
ipcMain.handle('ring:start', (_e, { number, busy, silenced }) => {
  if (!win) return
  if (!busy && !silenced) {   // pop up, the way a phone call does
    if (win.isMinimized()) win.restore()
    win.show(); win.setAlwaysOnTop(true); win.focus()
    setTimeout(() => win?.setAlwaysOnTop(false), 1500)
  }
  if (!win.isFocused()) win.flashFrame(true)
  if (!Notification.isSupported()) return
  ringNote?.close()
  const opts = { title: number || 'Incoming call', body: busy ? 'Incoming call · you are on another call' : 'Incoming call', silent: true }
  if (process.platform === 'win32' && app.isPackaged) opts.toastXml = callToast(number || 'Incoming call', busy, silenced)
  ringNote = new Notification(opts)
  ringNote.on('click', showWindow)
  ringNote.show()
})
ipcMain.handle('ring:stop', () => { ringNote?.close(); ringNote = null; win?.flashFrame(false) })

// ---- Another app's call (Teams, Zoom, WhatsApp, Skype…): which other apps are using the microphone right now ----
// Windows records every app's microphone use (what lights the taskbar's microphone icon): a LastUsedTimeStop of 0
// means "in use now". Packaged apps (Teams, WhatsApp) and desktop programs (NonPackaged) are both listed. Our own
// entry is left out. Returns the apps' names; empty when none (or not Windows).
const MIC_KEY = 'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\CapabilityAccessManager\\ConsentStore\\microphone'
ipcMain.handle('mic:others', () => new Promise((ok) => {
  if (process.platform !== 'win32') { ok([]); return }
  execFile('reg', ['query', MIC_KEY, '/s'], { windowsHide: true, maxBuffer: 8 * 1024 * 1024 }, (err, out) => {
    if (err) { ok([]); return }
    const apps = []
    let key = null, start = false, stop = null
    const flush = () => {
      if (key && start && stop === false && !/n2it|electron/i.test(key)) apps.push(key.split('\\').pop().split('#').pop())
    }
    for (const line of out.split(/\r?\n/)) {
      if (line.startsWith('HKEY_')) { flush(); key = line.trim(); start = false; stop = null; continue }
      const m = line.match(/^\s+(LastUsedTimeStart|LastUsedTimeStop)\s+REG_QWORD\s+0x([0-9a-f]+)/i)
      if (m) { const nonZero = /[1-9a-f]/i.test(m[2]); if (m[1] === 'LastUsedTimeStart') start = nonZero; else stop = nonZero }
    }
    flush(); ok(apps)
  })
}))
// The page asks for a number from a link that started the app once it is listening.
ipcMain.handle('links:pending', () => { const n = pendingDial; pendingDial = null; return n })
ipcMain.handle('links:settings', () => {
  if (process.platform === 'win32') shell.openExternal('ms-settings:defaultapps?registeredAppUser=N2IT%20Phone')
})
ipcMain.handle('links:status', () => ({
  platform: process.platform,
  tel: app.isDefaultProtocolClient('tel') || /n2it/i.test(app.getApplicationNameForProtocol('tel:')),
}))

const file = () => path.join(app.getPath('userData'), 'account.bin')

// Account JSON is encrypted with Windows DPAPI via safeStorage.
ipcMain.handle('account:load', () => {
  try { return JSON.parse(safeStorage.decryptString(fs.readFileSync(file()))) } catch { return null }
})
ipcMain.handle('account:save', (_e, acc) => fs.writeFileSync(file(), safeStorage.encryptString(JSON.stringify(acc))))
ipcMain.handle('app:version', () => app.getVersion())
ipcMain.handle('account:clear', () => { try { fs.unlinkSync(file()) } catch {} })

// Company contacts (extensions + shared FusionPBX contacts) from the PBX, fetched here rather than in the page:
// no CORS preflight, and the password never leaves the main process.
ipcMain.handle('directory:load', async () => {
  let acc
  try { acc = JSON.parse(safeStorage.decryptString(fs.readFileSync(file()))) } catch { return { error: 'Not signed in' } }
  const host = `${acc.tenant.trim().toLowerCase()}.voip.n2it.co.za`
  const auth = Buffer.from(`${acc.user.trim()}:${acc.pass}`).toString('base64')
  try {
    const r = await fetch(`https://${host}/app/n2it/contacts.php`,
      { headers: { Authorization: `Basic ${auth}` }, signal: AbortSignal.timeout(15000) })
    if (!r.ok) return { error: r.status === 401 ? 'Wrong extension or password' : `Server error ${r.status}` }
    return await r.json()
  } catch (e) { return { error: `Cannot reach ${host}` } }
})

// Chromium's separate audio process is a known cause of "NotReadableError: Could not start audio source" on some
// Windows PCs whose mic works in other apps; capture in the main process instead. Windows only: on Linux an audio
// fault then takes the whole app down (main-thread crash on Omarchy/Hyprland, 2026-10-09).
if (process.platform === 'win32') app.commandLine.appendSwitch('disable-features', 'AudioServiceOutOfProcess')
app.setAppUserModelId('za.co.n2it.softphone.desktop')   // Windows notifications need the installer's app id
// ---- Window + notification area (owner 2026-10-08: like other softphones, closing or minimising keeps the phone
// running in the notification area's hidden icons, so calls still ring) ----
const prefsFile = () => path.join(app.getPath('userData'), 'window.json')
let prefs = {}
const savePrefs = () => { try { fs.writeFileSync(prefsFile(), JSON.stringify(prefs)) } catch {} }
let tray = null, quitting = false, appState = { status: 'Starting…', inCall: false }
const startHidden = process.argv.includes('--hidden')   // started with Windows: straight to the notification area
function showWindow() { if (!win) return; if (win.isMinimized()) win.restore(); win.show(); win.focus() }
function toTray() {
  if (!win) return
  win.hide()
  if (process.platform === 'win32' && tray && !prefs.trayTipShown) {   // once: say where it went
    prefs.trayTipShown = true; savePrefs()
    tray.displayBalloon({ iconType: 'info', title: 'N2IT Phone is still running',
      content: 'Calls still ring. Open it again from the hidden icons (^) on the taskbar. Right-click > Quit to close it.' })
  }
}
function quitApp() {
  if (appState.inCall && dialog.showMessageBoxSync(win, { type: 'warning', buttons: ['Quit and hang up', 'Cancel'],
    defaultId: 1, cancelId: 1, title: 'N2IT Phone', message: 'You are on a call. Quit N2IT Phone and end the call?' }) !== 0) return
  quitting = true; app.quit()
}
function trayMenu() {
  tray?.setToolTip(`N2IT Phone · ${appState.status}`)
  tray?.setContextMenu(Menu.buildFromTemplate([
    { label: `N2IT Phone · ${appState.status}`, enabled: false },
    { type: 'separator' },
    { label: 'Open N2IT Phone', click: showWindow },
    { label: 'Quit', click: quitApp },
  ]))
}
function makeTray() {
  const img = nativeImage.createFromPath(path.join(__dirname, 'assets/icon.png'))
  tray = new Tray(img.resize({ width: process.platform === 'darwin' ? 18 : 16, quality: 'best' }))
  tray.on('click', () => (win?.isVisible() && win.isFocused() ? toTray() : showWindow()))
  tray.on('double-click', showWindow)
  trayMenu()
}
ipcMain.on('app:state', (_e, st) => {
  const next = { ...appState, ...st }
  if (next.status !== appState.status || next.inCall !== appState.inCall) { appState = next; trayMenu() }
})
// Start with Windows (in the notification area). On by default: a phone that is not running cannot ring.
const startup = () => prefs.startup !== false
ipcMain.handle('startup:get', () => startup())
ipcMain.handle('startup:set', (_e, on) => { prefs.startup = !!on; savePrefs(); applyStartup() })
function applyStartup() {
  if (!app.isPackaged || process.platform === 'linux') return
  app.setLoginItemSettings({ openAtLogin: startup(), args: ['--hidden'] })
}
/** Last size and place, if it is still on a screen (a monitor may have been unplugged). */
function savedBounds() {
  const b = prefs.bounds
  if (!b) return { width: 980, height: 680 }
  const on = screen.getAllDisplays().some(({ workArea: a }) =>
    b.x < a.x + a.width - 80 && b.x + b.width > a.x + 80 && b.y >= a.y - 20 && b.y < a.y + a.height - 80)
  return on ? b : { width: b.width, height: b.height }
}

app.whenReady().then(() => {
  if (!primary) return
  try { prefs = JSON.parse(fs.readFileSync(prefsFile(), 'utf8')) } catch {}
  registerLinksWindows(); applyStartup()
  // Microphone only; refuse every other permission request.
  session.defaultSession.setPermissionRequestHandler((_wc, perm, cb) => cb(perm === 'media'))
  win = new BrowserWindow({
    ...savedBounds(), minWidth: 360, minHeight: 560, show: false, title: 'N2IT Phone',
    backgroundColor: require('electron').nativeTheme.shouldUseDarkColors ? '#14171c' : '#f3f5f9',
    icon: path.join(__dirname, 'assets/icon.png'),
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, sandbox: false },
  })
  win.setMenuBarVisibility(false)
  win.once('ready-to-show', () => { if (!startHidden) { if (prefs.maximized) win.maximize(); win.show() } })
  const remember = () => { if (!win.isMaximized() && !win.isMinimized() && !win.isFullScreen()) prefs.bounds = win.getBounds() }
  win.on('resize', remember); win.on('move', remember)
  win.on('minimize', (e) => { e.preventDefault(); toTray() })
  win.on('close', (e) => {
    prefs.maximized = win.isMaximized(); savePrefs()
    if (!quitting) { e.preventDefault(); toTray() }
  })
  win.on('session-end', () => { quitting = true })   // Windows shutting down / signing out
  makeTray()
  win.loadFile(path.join(__dirname, 'index.html'))
})
app.on('before-quit', () => { quitting = true })
app.on('window-all-closed', () => app.quit())
