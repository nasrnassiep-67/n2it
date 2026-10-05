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

app.whenReady().then(() => {
  // Microphone only; refuse every other permission request.
  session.defaultSession.setPermissionRequestHandler((_wc, perm, cb) => cb(perm === 'media'))
  const win = new BrowserWindow({
    width: 380, height: 700, title: 'N2IT Phone',
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, sandbox: false },
  })
  win.setMenuBarVisibility(false)
  win.loadFile(path.join(__dirname, 'index.html'))
})
app.on('window-all-closed', () => app.quit())
