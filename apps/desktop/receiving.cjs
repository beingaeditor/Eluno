const fs = require('node:fs/promises');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const { constants } = require('node:fs');

// Only opaque handles cross IPC. The renderer never chooses filesystem paths.
exports.installReceiving = function (ipcMain, dialog, window, origin) {
  const handles = new Map();
  const check = event => {
    if (event.sender !== window.webContents || event.senderFrame !== window.webContents.mainFrame || new URL(event.senderFrame.url).origin !== origin) throw new Error('Untrusted window.');
  };
  const guarded = (name, action) => ipcMain.handle('receiving:' + name, async (event, ...args) => { check(event); return action(...args); });
  guarded('choose', async (name, size) => {
    if (typeof name !== 'string' || !Number.isSafeInteger(size) || size < 1) throw new Error('Invalid file.');
    if (handles.size >= 20) throw new Error('Finish or cancel an existing copy first.');
    const choice = await dialog.showOpenDialog(window, { title: 'Choose a folder for this copy', properties: ['openDirectory', 'createDirectory'] });
    if (choice.canceled) return null;
    const directory = choice.filePaths[0];
    const space = await fs.statfs(directory);
    if (space.bavail * space.bsize < size + 1024 * 1024) throw new Error('This folder does not have enough free space. Choose another destination.');
    name = name.replace(/[\x00-\x1f\x7f<>:"/\\|?*]/g, '_').replace(/[. ]+$/, '').slice(0, 120) || 'Eluno-file';
    if (/^(con|prn|aux|nul|com[0-9]|lpt[0-9])(?:\.|$)/i.test(name)) name = '_' + name;
    const id = randomUUID(), partial = path.join(directory, '.eluno-' + id + '.part');
    const file = await fs.open(partial, 'wx', 0o600);
    handles.set(id, { directory, name, partial, file, size, bytes: 0, busy: false });
    return { id, destination: path.basename(directory) || directory };
  });
  const operate = async (id, action) => {
    const h = handles.get(id);
    if (!h || h.busy) throw new Error('Destination is unavailable or busy.');
    h.busy = true;
    try { return await action(h); } finally { h.busy = false; }
  };
  guarded('write', (id, offset, data) => operate(id, async h => {
    const bytes = Buffer.from(data);
    if (offset !== h.bytes || bytes.length < 1 || bytes.length > 256 * 1024 || offset + bytes.length > h.size) throw new Error('Invalid copy offset.');
    let written = 0;
    while (written < bytes.length) { const result = await h.file.write(bytes, written, bytes.length - written, offset + written); if (!result.bytesWritten) throw new Error('The destination stopped accepting data.'); written += result.bytesWritten; }
    h.bytes += written; return h.bytes;
  }));
  guarded('finish', id => operate(id, async h => {
    if (h.bytes !== h.size) throw new Error('The copy is incomplete.');
    if (!h.closed) { await h.file.sync(); await h.file.close(); h.closed = true; }
    const ext = path.extname(h.name), stem = path.basename(h.name, ext);
    for (let n = 0; n < 10000; n++) {
      const name = n ? `${stem} (${n})${ext}` : h.name, target = path.join(h.directory, name);
      try {
        // Exclusive publication preserves an existing file, even if it appeared mid-transfer.
        try { await fs.link(h.partial, target); }
        catch (error) { if (error.code === 'EEXIST') throw error; await fs.copyFile(h.partial, target, constants.COPYFILE_EXCL); }
        await fs.unlink(h.partial); handles.delete(id); return name;
      } catch (error) { if (error.code !== 'EEXIST') throw error; }
    }
    throw new Error('Too many files with this name. Choose another folder.');
  }));
  guarded('cancel', id => operate(id, async h => { await h.file.close().catch(() => {}); await fs.unlink(h.partial).catch(() => {}); handles.delete(id); }));
  return async () => { for (const h of handles.values()) { await h.file.close().catch(() => {}); await fs.unlink(h.partial).catch(() => {}); } handles.clear(); };
};
