export function createTransfers({ api, notice, button, identity }) {
  const jobs = new Map();
  let room;
  const patch = async (id, action, extra = {}) => (await api('/api/transfers/' + id, { method: 'PATCH', data: { action, ...extra } })).json();
  const terminal = t => ['completed', 'cancelled', 'declined'].includes(t.status);
  async function destination(t) {
    if (window.elunoDesktop) {
      const handle = await window.elunoDesktop.choose(t.name, t.size);
      if (!handle) return null;
      return { label: handle.destination, write: (offset, bytes) => window.elunoDesktop.write(handle.id, offset, bytes), finish: () => window.elunoDesktop.finish(handle.id), cancel: () => window.elunoDesktop.cancel(handle.id) };
    }
    if (!window.showSaveFilePicker) throw new Error('Use the installed Eluno app to receive an approved copy with progress. This browser does not support choosing a writable destination.');
    const handle = await window.showSaveFilePicker({ suggestedName: t.name });
    const stream = await handle.createWritable();
    return { label: handle.name, write: (offset, bytes) => stream.write({ type: 'write', position: offset, data: bytes }), finish: () => stream.close(), cancel: () => stream.abort() };
  }
  async function receive(t) {
    let job = jobs.get(t.id);
    if (job?.running) return;
    if (!job) {
      const target = await destination(t); if (!target) return;
      job = { target, bytes: 0 }; jobs.set(t.id, job);
    }
    job.running = true; job.abort = new AbortController(); job.error = '';
    try {
      // A missed pause acknowledgement may leave the remote state receiving.
      if (t.status === 'receiving') await patch(t.id, 'pause');
      const { url } = await patch(t.id, t.status === 'offered' ? 'accept' : 'resume', { bytes: job.bytes });
      while (job.bytes < t.size) {
        const end = Math.min(job.bytes + 256 * 1024, t.size) - 1;
        const response = await fetch(url, { headers: { Range: `bytes=${job.bytes}-${end}` }, signal: job.abort.signal, cache: 'no-store' });
        if (!response.ok) throw new Error((await response.json().catch(() => ({}))).error || 'Source unavailable. Keep both devices open and resume.');
        const bytes = await response.arrayBuffer();
        if (bytes.byteLength !== end - job.bytes + 1) throw new Error('The source file changed. Cancel and share it again.');
        await job.target.write(job.bytes, bytes); job.bytes += bytes.byteLength;
        await patch(t.id, 'progress', { bytes: job.bytes });
      }
      if (!job.saved) { await job.target.finish(); job.saved = true; }
      await patch(t.id, 'complete');
    } catch (error) {
      job.error = error.name === 'AbortError' ? 'Paused. Resume while the source remains shared.' : error.message;
      await patch(t.id, 'pause', { error: job.error }).catch(() => {});
    } finally { job.running = false; render(room); }
  }
  async function cancel(t) {
    await patch(t.id, 'cancel');
    jobs.get(t.id)?.abort?.abort();
  }
  function render(next) {
    room = next;
    const list = document.getElementById('transfer-list'); list.replaceChildren();
    const transfers = room?.transfers || [];
    for (const [id, job] of jobs) {
      const t = transfers.find(t => t.id === id);
      if (!t || terminal(t)) {
        job.abort?.abort();
        if (!job.running) { if (!job.saved) void job.target.cancel().catch(() => {}); jobs.delete(id); }
      }
    }
    document.getElementById('transfers').hidden = !transfers.length;
    for (const t of transfers) {
      const receiving = t.receiverId === identity()?.id, job = jobs.get(t.id);
      const card = document.createElement('article'); card.className = 'transfer';
      const title = document.createElement('strong'); title.textContent = t.name;
      const detail = document.createElement('p'); detail.className = 'small';
      const peer = room.members.find(m => m.id === (receiving ? t.senderId : t.receiverId));
      detail.textContent = `${receiving ? 'From' : 'To'} ${peer?.name || 'Disconnected device'} · ${t.status} · ${(t.bytes / 1048576).toFixed(1)} / ${(t.size / 1048576).toFixed(1)} MB${job ? ' · ' + job.target.label : ''}`;
      const progress = document.createElement('progress'); progress.max = t.size; progress.value = t.bytes; progress.setAttribute('aria-label', t.name + ' transfer progress');
      const controls = document.createElement('div'); controls.className = 'actions';
      if (receiving && t.status === 'offered') { controls.append(button('Choose destination & accept', () => receive(t)), button('Decline', () => patch(t.id, 'decline'), 'text-button')); }
      if (receiving && !terminal(t) && t.status !== 'offered') {
        if (job?.running) controls.append(button('Pause', () => job.abort.abort()));
        else controls.append(button(job ? 'Resume' : 'Choose destination & restart', () => receive(t)));
      }
      if (!terminal(t)) controls.append(button('Cancel transfer', () => cancel(t), 'text-button'));
      card.append(title, detail, progress, controls);
      if (job?.error || t.error) { const error = document.createElement('p'); error.textContent = job?.error || t.error; card.append(error); }
      list.append(card);
    }
  }
  async function offer(file) {
    const dialog = document.getElementById('send-dialog'), select = document.getElementById('send-device');
    select.replaceChildren();
    for (const device of room.members.filter(m => m.id !== identity().id && m.online)) { const option = document.createElement('option'); option.value = device.id; option.textContent = device.name; select.append(option); }
    if (!select.options.length) { notice('Connect another device before sending a copy.'); return; }
    document.getElementById('send-name').textContent = file.name;
    dialog.showModal();
    document.getElementById('send-confirm').onclick = async () => {
      try { await api('/api/transfers', { method: 'POST', data: { fileId: file.id, receiverId: select.value } }); dialog.close(); notice('Offer sent. The receiving device chooses where to save it.'); } catch (error) { notice(error.message); dialog.close(); }
    };
  }
  return { render, offer };
}
