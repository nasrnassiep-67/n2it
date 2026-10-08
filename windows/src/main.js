const { app, BrowserWindow, ipcMain, Notification, safeStorage, session, shell } = require('electron')
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
  if (win) { if (win.isMinimized()) win.restore(); win.show(); win.focus() }
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
    if (win && (what === 'answer' || what === 'open')) { if (win.isMinimized()) win.restore(); win.show(); win.focus() }
    return
  }
  dial(linkIn(argv)); if (win) { if (win.isMinimized()) win.restore(); win.focus() }
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
  ringNote.on('click', () => { if (win) { if (win.isMinimized()) win.restore(); win.show(); win.focus() } })
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
// Windows PCs whose mic works in other apps; capture in the main process instead.
app.commandLine.appendSwitch('disable-features', 'AudioServiceOutOfProcess')
app.setAppUserModelId('za.co.n2it.softphone.desktop')   // Windows notifications need the installer's app id
app.whenReady().then(() => {
  if (!primary) return
  registerLinksWindows()
  // Microphone only; refuse every other permission request.
  session.defaultSession.setPermissionRequestHandler((_wc, perm, cb) => cb(perm === 'media'))
  win = new BrowserWindow({
    width: 380, height: 700, title: 'N2IT Phone', icon: path.join(__dirname, 'assets/icon.png'),
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, sandbox: false },
  })
  win.setMenuBarVisibility(false)
  win.loadFile(path.join(__dirname, 'index.html'))
})
app.on('window-all-closed', () => app.quit())
