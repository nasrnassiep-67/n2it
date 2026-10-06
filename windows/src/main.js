const { app, BrowserWindow, ipcMain, safeStorage, session } = require('electron')
const fs = require('fs')
const path = require('path')

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
  // Microphone only; refuse every other permission request.
  session.defaultSession.setPermissionRequestHandler((_wc, perm, cb) => cb(perm === 'media'))
  const win = new BrowserWindow({
    width: 380, height: 700, title: 'N2IT Phone', icon: path.join(__dirname, 'assets/icon.png'),
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, sandbox: false },
  })
  win.setMenuBarVisibility(false)
  win.loadFile(path.join(__dirname, 'index.html'))
})
app.on('window-all-closed', () => app.quit())
