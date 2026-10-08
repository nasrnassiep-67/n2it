const { contextBridge, ipcRenderer } = require('electron')
contextBridge.exposeInMainWorld('store', {
  load: () => ipcRenderer.invoke('account:load'),
  save: (a) => ipcRenderer.invoke('account:save', a),
  clear: () => ipcRenderer.invoke('account:clear'),
  directory: () => ipcRenderer.invoke('directory:load'),
  version: () => ipcRenderer.invoke('app:version'),
})
// Incoming calls: window pop-up + Windows notification (main.js), its buttons, and other apps' microphone use.
contextBridge.exposeInMainWorld('callUi', {
  ringStart: (o) => ipcRenderer.invoke('ring:start', o),
  ringStop: () => ipcRenderer.invoke('ring:stop'),
  micOthers: () => ipcRenderer.invoke('mic:others'),
  onAction: (cb) => ipcRenderer.on('call:action', (_e, a) => cb(a)),
})
// Phone links (tel:, callto:, sip:) clicked elsewhere: the number arrives here.
contextBridge.exposeInMainWorld('links', {
  onDial: (cb) => ipcRenderer.on('dial', (_e, n) => cb(n)),
  pending: () => ipcRenderer.invoke('links:pending'),
  settings: () => ipcRenderer.invoke('links:settings'),
  status: () => ipcRenderer.invoke('links:status'),
})
