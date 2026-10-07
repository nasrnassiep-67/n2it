const { app, BrowserWindow, ipcMain, safeStorage, session, shell } = require('electron')
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
app.on('second-instance', (_e, argv) => { dial(linkIn(argv)); if (win) { if (win.isMinimized()) win.restore(); win.focus() } })
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
  })
}
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
