const { app, BrowserWindow, Menu, dialog } = require('electron');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
let companion, quitting = false, window;

if (!app.requestSingleInstanceLock()) app.quit();
else {
  app.on('second-instance', () => { if (window) { if (window.isMinimized()) window.restore(); window.focus(); } });
  app.whenReady().then(async () => {
    try {
      const root = app.getAppPath();
      const { createElunoServer } = await import(pathToFileURL(path.join(root, 'packages/core/server.mjs')).href);
      const { loadIdentity } = await import(pathToFileURL(path.join(root, 'packages/core/tls.mjs')).href);
      const directory = process.env.ELUNO_DATA_DIR || (app.isPackaged ? app.getPath('userData') : path.join(root, '.eluno-local/desktop'));
      companion = await createElunoServer({ port: 0, lan: true, tls: await loadIdentity(directory), onDiscoveryWarning: () => {} });
      if (process.argv.includes('--smoke-test')) {
        const health = await (await fetch(companion.url + '/api/health')).json();
        if (health.product !== 'Eluno' || !health.lan || health.protocol !== 1) throw new Error('Packaged runtime health check failed.');
        console.log('ELUNO_SMOKE_OK ' + JSON.stringify({ product: health.product, version: health.version, protocol: health.protocol, encryptedLan: health.lan }));
        await companion.close(); companion = null; app.quit(); return;
      }
      window = new BrowserWindow({ width: 1250, height: 860, minWidth: 720, minHeight: 580, title: 'Eluno', backgroundColor: '#f5f4ec', icon: path.join(root, 'apps/desktop/icon.ico'), webPreferences: { nodeIntegration: false, contextIsolation: true, sandbox: true, webSecurity: true } });
      const allowedOrigin = new URL(companion.url).origin;
      window.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
      window.webContents.on('will-navigate', (event, url) => { if (new URL(url).origin !== allowedOrigin) event.preventDefault(); });
      window.webContents.session.setPermissionRequestHandler((_contents, _permission, callback) => callback(false));
      Menu.setApplicationMenu(Menu.buildFromTemplate([
        { label: 'Eluno', submenu: [{ label: 'About Eluno', click: () => dialog.showMessageBox(window, { type: 'info', title: 'Eluno', message: `Eluno ${app.getVersion()}`, detail: 'Private sharing across your devices. Keep the sharing device open. Your files stay on their source device.' }) }, { type: 'separator' }, { role: 'quit' }] },
        { label: 'Edit', submenu: [{ role: 'undo' }, { role: 'redo' }, { role: 'cut' }, { role: 'copy' }, { role: 'paste' }, { role: 'selectAll' }] },
        { label: 'View', submenu: [{ role: 'resetZoom' }, { role: 'zoomIn' }, { role: 'zoomOut' }, { role: 'togglefullscreen' }] }
      ]));
      await window.loadURL(companion.url);
      console.log(`Eluno desktop ready: ${companion.url}`);
    } catch (error) {
      if (process.argv.includes('--smoke-test')) { console.error(error.message); if (companion) await companion.close(); companion = null; app.exit(1); return; }
      dialog.showErrorBox('Eluno could not start', error.message);
      app.quit();
    }
  });
  app.on('window-all-closed', () => app.quit());
  app.on('before-quit', event => {
    if (companion && !quitting) { event.preventDefault(); quitting = true; companion.close().finally(() => app.quit()); }
  });
}
