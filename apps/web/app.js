const $ = id => document.getElementById(id);
let identity, state, version = -1, stopped = false, qrUrl, openingId, renderKey, openGeneration = 0;
const localFiles = new Map(), serving = new Set(), positions = new Map(), thumbnails = new Map();
const joinCode = new URLSearchParams(location.hash.slice(1)).get('join');
if (joinCode && /^\d{6}$/.test(joinCode)) $('pair-code').value = joinCode;
history.replaceState(null, '', '/');
$('device-name').value = localStorage.getItem('eluno.deviceName') || 'My computer';

function notice(message) { $('notice').textContent = message; $('notice').hidden = !message; }
async function api(path, { method = 'GET', data, raw } = {}) {
  const headers = identity ? { Authorization: `Bearer ${identity.token}` } : {};
  if (data !== undefined) headers['Content-Type'] = 'application/json';
  const response = await fetch(path, { method, headers, body: data === undefined ? raw : JSON.stringify(data), cache: 'no-store' });
  if (!response.ok) {
    const error = await response.json().catch(() => ({}));
    throw Object.assign(new Error(error.error || 'Connection interrupted. Try again.'), { status: response.status });
  }
  return response;
}
async function run(action) {
  notice('');
  try { await action(); } catch (error) { notice(error.message); }
}
function button(label, action, className = 'secondary') {
  const el = document.createElement('button'); el.textContent = label; el.className = className;
  el.addEventListener('click', () => run(action)); return el;
}
function closeViewer() {
  openGeneration++;
  const video = $('viewer-content').querySelector('video');
  if (video) { if (openingId && Number.isFinite(video.currentTime)) positions.set(openingId, video.currentTime); video.pause(); video.removeAttribute('src'); video.load(); }
  $('viewer-content').replaceChildren(); openingId = null;
  if ($('viewer').open) $('viewer').close();
}
async function updateQr() {
  if (qrUrl) URL.revokeObjectURL(qrUrl);
  const response = await api('/api/pairing');
  qrUrl = URL.createObjectURL(await response.blob()); $('qr').src = qrUrl; $('qr').hidden = false;
}
async function loadInvitation() {
  const { origins, lan } = await (await api('/api/addresses')).json();
  $('lan-note').textContent = lan ? 'On your Android device, open Eluno → Scan computer invitation. Use the same Wi-Fi, then approve the request here.' : 'Browser preview: open Eluno in another tab and enter this code. The installed Windows app connects your Android devices.';
  if (lan && !origins.length) { $('qr').hidden = true; notice('Connect your computer to a private Wi-Fi or home network, then restart Eluno to invite your Android device.'); return; }
  await updateQr();
}
function render(next) {
  const oldRoom = state?.room?.id;
  state = next; version = next.version;
  $('onboarding').hidden = Boolean(identity);
  $('connect').hidden = Boolean(next.room || next.pending);
  $('pending').hidden = !next.pending;
  $('session').hidden = !next.room;
  document.body.classList.toggle('connected', Boolean(next.room));
  $('hello-name').textContent = next.self.name;
  if (!next.room) {
    if (oldRoom) { localFiles.clear(); closeViewer(); positions.clear(); thumbnails.clear(); notice('Connection ended. You can connect again whenever you’re ready.'); }
    renderKey = null; return;
  }
  const room = next.room;
  if (openingId && !room.files.some(f => f.id === openingId)) { closeViewer(); notice('This item is no longer shared.'); }
  const owner = room.ownerId === identity.id;
  $('invitation').hidden = !owner;
  const key = JSON.stringify([room.id, room.code, room.pending, room.members, room.files]);
  if (renderKey === key) return;
  const prior = renderKey; renderKey = key;
  $('members').textContent = room.members.map(m => m.name + (m.id === identity.id ? ' (this device)' : '') + (m.online ? '' : ' · offline')).join('  ↔  ');
  $('expires').textContent = 'For your privacy, this connection ends at ' + new Date(room.expiresAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) + '.';
  $('device-actions').replaceChildren();
  if (owner) for (const peer of room.members.filter(m => m.id !== identity.id)) $('device-actions').append(button('Remove ' + peer.name, () => api('/api/members/' + peer.id, { method: 'DELETE' }), 'text-button'));
  $('room-code').textContent = room.code || '';
  $('code-expiry').textContent = room.pairExpiresAt > Date.now() ? 'Code valid until ' + new Date(room.pairExpiresAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : 'Code expired. Get a new code below.';
  if (owner && (!prior || oldRoom !== room.id || $('qr').dataset.code !== room.code)) {
    $('qr').dataset.code = room.code; run(loadInvitation);
  }
  $('requests').replaceChildren();
  for (const peer of room.pending) {
    const request = document.createElement('div'); request.className = 'request';
    const title = document.createElement('strong'); title.textContent = `${peer.name} wants to connect.`;
    const actions = document.createElement('div'); actions.className = 'actions';
    for (const [label, allow] of [['Approve', true], ['Decline', false]]) actions.append(button(label, () => api('/api/approve', { method: 'POST', data: { deviceId: peer.id, allow } })));
    request.append(title, actions); $('requests').append(request);
  }
  for (const id of thumbnails.keys()) if (!room.files.some(f => f.id === id)) thumbnails.delete(id);
  renderFiles();
}
function renderFiles() {
  const room = state?.room; if (!room) return;
  const query = $('search').value.trim().toLocaleLowerCase();
  const kind = $('media-filter').value;
  const shown = room.files.filter(f => (!kind || f.type.startsWith(kind)) && (f.name + ' ' + (room.members.find(m => m.id === f.ownerId)?.name || '')).toLocaleLowerCase().includes(query));
  $('item-count').textContent = `${shown.length} of ${room.files.length} items`;
  $('files').replaceChildren();
  if (!shown.length) {
    const empty = document.createElement('div'); empty.className = 'empty';
    const heading = document.createElement('strong'); heading.textContent = room.files.length ? 'No matching items.' : 'Something good starts here.';
    const hint = document.createElement('p'); hint.textContent = room.files.length ? 'Try another name or show all media.' : 'Add a photo or video to make it available on your connected screens.';
    empty.append(heading, hint); $('files').append(empty);
  }
  for (const file of shown) {
    const item = document.createElement('div'); item.className = 'file';
    const icon = document.createElement('div'); icon.className = 'file-icon'; icon.textContent = file.type.startsWith('video/') ? '▷' : '▧';
    if (thumbnails.has(file.id)) { const image = document.createElement('img'); image.src = thumbnails.get(file.id); image.alt = ''; icon.replaceChildren(image); }
    const info = document.createElement('div'); info.className = 'file-info';
    const name = document.createElement('strong'); name.textContent = file.name;
    const meta = document.createElement('small');
    meta.textContent = `${(file.size / 1024 / 1024).toFixed(1)} MB · ${room.members.find(m => m.id === file.ownerId)?.name || 'Device'}`;
    info.append(name, meta);
    const actions = document.createElement('div'); actions.className = 'file-actions';
    actions.append(button(file.type.startsWith('video/') ? 'Play' : 'View', () => openFile(file)));
    if (file.allowDownload) actions.append(button('Save copy', () => saveCopy(file)));
    if (file.ownerId === identity.id) actions.append(button(file.allowDownload ? 'Disable copies' : 'Allow copies', () => api('/api/files/' + file.id, { method: 'PATCH', data: { allowDownload: !file.allowDownload } }), 'text-button'));
    if (file.ownerId === identity.id) actions.append(button('Stop', async () => { await api('/api/files/' + file.id, { method: 'DELETE' }); localFiles.delete(file.id); }, 'text-button stop'));
    item.append(icon, info, actions); $('files').append(item);
  }
}
async function serve(read) {
  if (serving.has(read.id)) return;
  serving.add(read.id);
  try {
    const file = localFiles.get(read.fileId);
    if (!file) return;
    await api('/api/chunks/' + read.id, { method: 'POST', raw: await file.slice(read.start, read.end + 1).arrayBuffer() });
  } catch (error) { if (error.status !== 410) notice(error.message); }
  finally { serving.delete(read.id); }
}
async function poll() {
  while (!stopped && identity) {
    try {
      const next = await (await api('/api/events?since=' + version)).json();
      render(next);
      for (const read of next.reads) void serve(read);
    } catch (error) {
      notice(error.message + ' Eluno will retry while this screen is open.');
      if (error.status === 401) { stopped = true; closeViewer(); identity = null; state = null; localFiles.clear(); positions.clear(); thumbnails.clear(); $('onboarding').hidden = false; for (const id of ['connect', 'pending', 'session']) $(id).hidden = true; document.body.classList.remove('connected'); break; }
      await new Promise(resolve => setTimeout(resolve, 1500));
    }
  }
}
async function addFiles(files) {
  const list = [...files];
  if (!list.length) return;
  const fallback = { mp4: 'video/mp4', webm: 'video/webm', jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', webp: 'image/webp' };
  const metadata = list.map(f => ({ name: f.name, size: f.size, type: f.type || fallback[f.name.split('.').pop().toLowerCase()] || 'application/octet-stream', allowDownload: $('allow-copies').checked }));
  const added = await (await api('/api/files', { method: 'POST', data: { files: metadata } })).json();
  added.files.forEach((f, i) => localFiles.set(f.id, list[i]));
}
async function openFile(file) {
  if (!file) return;
  closeViewer(); const generation = openGeneration;
  const opened = await (await api('/api/files/' + file.id + '/open', { method: 'POST' })).json();
  if (generation !== openGeneration || !state?.room?.files.some(f => f.id === file.id)) return;
  openingId = file.id;
  $('viewer-title').textContent = file.name;
  $('viewer-error').hidden = true; $('retry-viewer').hidden = true;
  $('photo-controls').hidden = !file.type.startsWith('image/');
  const element = document.createElement(file.type.startsWith('video/') ? 'video' : 'img');
  if (element.tagName === 'VIDEO') { element.controls = true; element.playsInline = true; element.preload = 'metadata'; element.addEventListener('loadedmetadata', () => { const position = positions.get(file.id); if (position && position < element.duration - 1) element.currentTime = position; }); }
  else { element.alt = file.name; element.addEventListener('load', () => { if (generation !== openGeneration) return; const canvas = document.createElement('canvas'); canvas.width = 96; canvas.height = 72; canvas.getContext('2d').drawImage(element, 0, 0, 96, 72); thumbnails.set(file.id, canvas.toDataURL('image/webp')); if (thumbnails.size > 50) thumbnails.delete(thumbnails.keys().next().value); renderFiles(); }); }
  element.addEventListener('error', () => {
    $('viewer-error').textContent = 'This item could not open. Keep Eluno open on the sharing device and try again. If it still fails, this device may not support its format.';
    $('viewer-error').hidden = false; $('retry-viewer').hidden = false;
  });
  element.src = opened.url; $('viewer-content').append(element); $('viewer').showModal();
}
async function saveCopy(file) {
  const opened = await (await api('/api/files/' + file.id + '/open', { method: 'POST', data: { purpose: 'download' } })).json();
  const link = document.createElement('a'); link.href = opened.url; link.download = file.name; document.body.append(link); link.click(); link.remove();
  notice('Your copy is downloading. Keep both devices open until it finishes.');
}
async function movePhoto(delta) {
  const photos = state.room.files.filter(f => f.type.startsWith('image/'));
  const index = photos.findIndex(f => f.id === openingId);
  if (photos.length) await openFile(photos[(index + delta + photos.length) % photos.length]);
}
$('register').addEventListener('submit', event => { event.preventDefault(); run(async () => {
  identity = await (await api('/api/devices', { method: 'POST', data: { name: $('device-name').value } })).json();
  localStorage.setItem('eluno.deviceName', $('device-name').value);
  stopped = false; void poll();
}); });
$('create-room').addEventListener('click', () => run(() => api('/api/rooms', { method: 'POST' })));
$('join').addEventListener('submit', event => { event.preventDefault(); run(() => api('/api/join', { method: 'POST', data: { code: $('pair-code').value } })); });
for (const id of ['leave', 'cancel-join']) $(id).addEventListener('click', () => run(() => api('/api/leave', { method: 'POST' })));
$('renew').addEventListener('click', () => run(() => api('/api/renew-code', { method: 'POST' })));
$('search').addEventListener('input', renderFiles);
$('media-filter').addEventListener('change', renderFiles);
$('help-open').addEventListener('click', () => $('help').showModal());
$('help-close').addEventListener('click', () => $('help').close());
$('diagnostics').addEventListener('click', () => run(async () => {
  if (!state?.room) return notice('Connect your devices before saving a connection report.');
  const report = await (await api('/api/diagnostics')).json();
  const url = URL.createObjectURL(new Blob([JSON.stringify(report, null, 2)], { type: 'application/json' }));
  const link = document.createElement('a'); link.href = url; link.download = 'eluno-connection-report.json'; link.click(); setTimeout(() => URL.revokeObjectURL(url), 1000);
}));
setInterval(() => { if (state?.room?.pairExpiresAt <= Date.now()) $('code-expiry').textContent = 'Invitation expired. Get a new code below.'; }, 1000);
$('file-input').addEventListener('change', event => { const files = [...event.target.files]; event.target.value = ''; run(() => addFiles(files)); });
$('close-viewer').addEventListener('click', closeViewer);
$('viewer').addEventListener('cancel', event => { event.preventDefault(); closeViewer(); });
$('retry-viewer').addEventListener('click', () => run(() => openFile(state.room.files.find(f => f.id === openingId))));
$('previous-photo').addEventListener('click', () => run(() => movePhoto(-1)));
$('next-photo').addEventListener('click', () => run(() => movePhoto(1)));
$('zoom-photo').addEventListener('click', () => $('viewer-content').querySelector('img')?.classList.toggle('zoomed'));
$('samples').addEventListener('click', () => run(async () => {
  $('samples').disabled = true;
  try {
    const canvas = document.createElement('canvas'); canvas.width = 640; canvas.height = 360;
    const ctx = canvas.getContext('2d');
    const draw = tick => { ctx.fillStyle = '#17624c'; ctx.fillRect(0, 0, 640, 360); ctx.fillStyle = '#eee9cf'; ctx.font = '52px Georgia'; ctx.fillText('Hello from Eluno.', 65, 160); ctx.fillStyle = '#d89f59'; ctx.beginPath(); ctx.arc(90 + tick % 440, 245, 20, 0, Math.PI * 2); ctx.fill(); };
    draw(0);
    const photo = await new Promise(resolve => canvas.toBlob(resolve, 'image/png'));
    const files = [new File([photo], 'Eluno sample photo.png', { type: 'image/png' })];
    if (window.MediaRecorder && canvas.captureStream && MediaRecorder.isTypeSupported('video/webm;codecs=vp8')) {
      const stream = canvas.captureStream(15), parts = [];
      const recorder = new MediaRecorder(stream, { mimeType: 'video/webm;codecs=vp8' });
      recorder.ondataavailable = event => { if (event.data.size) parts.push(event.data); };
      const ended = new Promise(resolve => { recorder.onstop = resolve; });
      recorder.start(); let tick = 0;
      const timer = setInterval(() => draw(tick += 15), 65);
      await new Promise(resolve => setTimeout(resolve, 2500));
      clearInterval(timer); recorder.stop(); await ended; stream.getTracks().forEach(t => t.stop());
      files.push(new File(parts, 'Eluno sample video.webm', { type: 'video/webm' }));
    }
    await addFiles(files);
  } finally { $('samples').disabled = false; }
}));
window.addEventListener('pagehide', () => {
  stopped = true;
  if (identity) fetch('/api/leave', { method: 'POST', headers: { Authorization: `Bearer ${identity.token}` }, keepalive: true }).catch(() => {});
});
