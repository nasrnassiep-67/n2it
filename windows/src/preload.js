const { contextBridge, ipcRenderer } = require('electron')
contextBridge.exposeInMainWorld('store', {
  load: () => ipcRenderer.invoke('account:load'),
  save: (a) => ipcRenderer.invoke('account:save', a),
  clear: () => ipcRenderer.invoke('account:clear'),
})
