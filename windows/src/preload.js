const { contextBridge, ipcRenderer } = require('electron')
contextBridge.exposeInMainWorld('store', {
  load: () => ipcRenderer.invoke('account:load'),
  save: (a) => ipcRenderer.invoke('account:save', a),
  clear: () => ipcRenderer.invoke('account:clear'),
  directory: () => ipcRenderer.invoke('directory:load'),
})
// Phone links (tel:, callto:, sip:) clicked elsewhere: the number arrives here.
contextBridge.exposeInMainWorld('links', {
  onDial: (cb) => ipcRenderer.on('dial', (_e, n) => cb(n)),
  pending: () => ipcRenderer.invoke('links:pending'),
  settings: () => ipcRenderer.invoke('links:settings'),
  status: () => ipcRenderer.invoke('links:status'),
})
