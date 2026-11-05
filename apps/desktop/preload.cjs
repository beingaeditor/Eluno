const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('elunoDesktop', {
  choose: (name, size) => ipcRenderer.invoke('receiving:choose', name, size),
  write: (id, offset, bytes) => ipcRenderer.invoke('receiving:write', id, offset, bytes),
  finish: id => ipcRenderer.invoke('receiving:finish', id),
  cancel: id => ipcRenderer.invoke('receiving:cancel', id)
});
