import http from 'node:http';
import https from 'node:https';
import { readFile } from 'node:fs/promises';
import { randomBytes, randomInt, randomUUID } from 'node:crypto';
import { networkInterfaces } from 'node:os';
import { once } from 'node:events';
import QRCode from 'qrcode';
import { CHUNK_BYTES, MEDIA_TYPES, MODULES, PROTOCOL_VERSION, LIMITS, safeDownloadName } from '../protocol/index.mjs';
import { advertise } from './discovery.mjs';

export { CHUNK_BYTES };
const TYPES = new Set(MEDIA_TYPES);
const secret = () => randomBytes(24).toString('base64url');
const fail = (status, message) => { throw Object.assign(new Error(message), { status }); };
const cleanName = value => typeof value === 'string' && value.trim().length > 0 && value.length <= 120;
const json = (res, status, body) => {
  if (res.destroyed || res.writableEnded) return;
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(body));
};

export function parseRange(header, size) {
  if (!header) return { start: 0, end: size - 1, partial: false };
  const match = /^bytes=(\d*)-(\d*)$/.exec(header);
  if (!match || (!match[1] && !match[2])) fail(416, 'Use one valid byte range.');
  let start = match[1] ? Number(match[1]) : Math.max(0, size - Number(match[2]));
  let end = match[1] && match[2] ? Math.min(Number(match[2]), size - 1) : size - 1;
  if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start < 0 || start >= size || end < start) fail(416, 'Range is outside this file.');
  return { start, end, partial: true };
}

async function body(req, limit) {
  const chunks = [];
  let length = 0;
  for await (const chunk of req) {
    length += chunk.length;
    if (length > limit) fail(413, 'Request is too large.');
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}
async function input(req) {
  try { const value = JSON.parse((await body(req, 64 * 1024)).toString()); if (!value || typeof value !== 'object' || Array.isArray(value)) fail(400, 'Use a JSON object.'); return value; }
  catch (error) { if (error.status) throw error; fail(400, 'Invalid JSON.'); }
}

export async function createElunoServer(options = {}) {
  const now = options.now ?? Date.now;
  const pairTtl = options.pairTtl ?? 5 * 60_000;
  const sessionTtl = options.sessionTtl ?? 8 * 60 * 60_000;
  const readTimeout = options.readTimeout ?? 12_000;
  const devices = new Map(), rooms = new Map(), grants = new Map(), reads = new Map(), attempts = new Map(), streams = new Map();
  const assets = new Map(await Promise.all(['index.html', 'app.js', 'styles.css'].map(async name => [
    '/' + (name === 'index.html' ? '' : name),
    { data: await readFile(new URL('../../apps/web/' + name, import.meta.url)), type: name.endsWith('.js') ? 'text/javascript' : name.endsWith('.css') ? 'text/css' : 'text/html' }
  ])));
  const addresses = ['127.0.0.1', 'localhost', ...Object.values(networkInterfaces()).flat().filter(n => n.family === 'IPv4' && !n.internal).map(n => n.address)];
  let port, securePort, stopAdvertising;
  const lanAddresses = [...new Set(addresses.filter(a => /^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)/.test(a)))].slice(0, 12);
  const wake = d => { d.version++; for (const done of [...d.waiters]) done(); };
  const broadcast = r => { for (const id of r.members) { const d = devices.get(id); if (d) wake(d); } };
  const activeRoom = d => {
    const r = rooms.get(d.roomId);
    if (!r || r.expiresAt <= now()) fail(409, 'Session ended. Connect your devices again.');
    return r;
  };
  const invalidate = predicate => {
    for (const [key, g] of grants) if (predicate(g)) grants.delete(key);
    for (const r of [...reads.values()]) if (predicate(r)) r.reject(Object.assign(new Error('Sharing stopped or session ended.'), { status: 410 }));
    for (const [res, stream] of streams) if (predicate(stream) && res.headersSent) res.destroy();
  };
  const removeMember = (r, id) => {
    const d = devices.get(id);
    r.members.delete(id);
    for (const [key, file] of r.files) if (file.ownerId === id) r.files.delete(key);
    invalidate(g => g.roomId === r.id && (g.sourceId === id || g.viewerId === id));
    if (d) { d.roomId = null; wake(d); }
    broadcast(r);
  };
  const endRoom = r => {
    for (const id of [...r.members]) removeMember(r, id);
    for (const id of r.pending) { const d = devices.get(id); if (d) { d.pendingRoom = null; wake(d); } }
    rooms.delete(r.id);
  };
  const sweep = () => {
    for (const r of rooms.values()) {
      if (r.expiresAt <= now()) { endRoom(r); continue; }
      for (const id of [...r.pending]) {
        const d = devices.get(id);
        if (!d || d.pendingAt + 60_000 <= now()) {
          r.pending.delete(id);
          if (d) { d.pendingRoom = null; wake(d); }
          broadcast(r);
        }
      }
    }
    for (const [key, g] of grants) if (g.expiresAt <= now()) grants.delete(key);
    for (const [key, a] of attempts) if (a.expiresAt <= now()) attempts.delete(key);
    for (const [id, d] of devices) if (d.seenAt + sessionTtl <= now() && !d.roomId && !d.pendingRoom) devices.delete(id);
  };
  const snapshot = d => {
    const r = rooms.get(d.roomId);
    return {
      version: d.version, self: { id: d.id, name: d.name }, pending: Boolean(d.pendingRoom),
      room: r ? {
        id: r.id, ownerId: r.ownerId, code: d.id === r.ownerId ? r.code : null,
        pairExpiresAt: r.pairExpiresAt, expiresAt: r.expiresAt,
        members: [...r.members].map(id => { const p = devices.get(id); return { id, name: p.name, online: p.seenAt + 20_000 > now() }; }),
        pending: d.id === r.ownerId ? [...r.pending].map(id => ({ id, name: devices.get(id).name })) : [],
        files: [...r.files.values()].map(f => ({ id: f.id, name: f.name, type: f.type, size: f.size, ownerId: f.ownerId, allowDownload: f.allowDownload }))
      } : null,
      reads: [...reads.values()].filter(r => r.sourceId === d.id).map(r => ({ id: r.id, fileId: r.fileId, start: r.start, end: r.end }))
    };
  };
  const rate = (req, scope, limit) => {
    const key = scope + req.socket.remoteAddress;
    let a = attempts.get(key);
    if (!a || a.expiresAt <= now()) { a = { count: 0, expiresAt: now() + 60_000 }; attempts.set(key, a); }
    if (++a.count > limit) fail(429, 'Too many attempts. Wait a minute and try again.');
  };
  const requestChunk = (g, file, start, end, stream) => new Promise((resolve, reject) => {
    const id = randomUUID();
    const finish = (fn, value) => {
      clearTimeout(timer); reads.delete(id); stream.off('close', cancelled); fn(value);
    };
    const cancelled = () => finish(reject, Object.assign(new Error('Viewer disconnected.'), { status: 499 }));
    const timer = setTimeout(() => finish(reject, Object.assign(new Error('Source unavailable. Keep Eluno open on the sharing device and try again.'), { status: 504 })), readTimeout);
    stream.once('close', cancelled);
    reads.set(id, { ...g, id, fileId: file.id, start, end, resolve: b => finish(resolve, b), reject: e => finish(reject, e) });
    wake(devices.get(g.sourceId));
  });

  const handler = async (req, res) => {
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('X-Frame-Options', 'DENY');
    res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' blob: data:; media-src 'self' blob:; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'");
    try {
      sweep();
      const secure = Boolean(req.socket.encrypted);
      if (!(secure ? addresses : ['127.0.0.1', 'localhost']).some(address => req.headers.host === `${address}:${secure ? securePort : port}`)) fail(403, 'Unrecognized local address.');
      const origin = `${secure ? 'https' : 'http'}://${req.headers.host}`;
      if (req.headers.origin && req.headers.origin !== origin) fail(403, 'Open Eluno directly to connect.');
      if (req.headers['sec-fetch-site'] === 'cross-site') fail(403, 'Cross-site requests are not allowed.');
      const url = new URL(req.url, origin);
      if (req.method === 'GET' && assets.has(url.pathname)) {
        const asset = assets.get(url.pathname);
        res.writeHead(200, { 'Content-Type': asset.type }); res.end(asset.data); return;
      }
      if (req.method === 'GET' && url.pathname === '/api/health') {
        json(res, 200, { product: 'Eluno', version: '0.2.0', protocol: PROTOCOL_VERSION, lan: Boolean(securePort), chunkBytes: CHUNK_BYTES, modules: MODULES }); return;
      }
      if (req.method === 'POST' && url.pathname === '/api/devices') {
        rate(req, 'register', 30);
        if (devices.size >= LIMITS.devices) fail(503, 'Device limit reached. Restart Eluno after ending your connections.');
        const { name } = await input(req);
        if (!cleanName(name)) fail(400, 'Enter a device name (1–120 characters).');
        const d = { id: randomUUID(), token: secret(), name: name.trim(), version: 0, seenAt: now(), waiters: new Set() };
        devices.set(d.id, d);
        json(res, 201, { id: d.id, token: d.token }); return;
      }
      if (url.pathname.startsWith('/media/')) {
        if (!['GET', 'HEAD'].includes(req.method)) fail(405, 'Use GET or HEAD.');
        const g = grants.get(url.searchParams.get('ticket'));
        const room = g && rooms.get(g.roomId);
        const file = room?.files.get(url.pathname.slice(7));
        if (!g || !file || g.fileId !== file.id || !room.members.has(g.viewerId) || !room.members.has(g.sourceId) || g.expiresAt <= now()) fail(410, 'Access expired or sharing stopped. Open this item again.');
        if (devices.get(g.sourceId).seenAt + 20_000 < now()) fail(503, 'The sharing device is offline. Reopen Eluno there.');
        let range;
        try { range = parseRange(req.headers.range, file.size); }
        catch (error) { res.setHeader('Content-Range', `bytes */${file.size}`); throw error; }
        const headers = { 'Content-Type': file.type, 'Accept-Ranges': 'bytes', 'Content-Length': range.end - range.start + 1 };
        if (g.purpose === 'download') headers['Content-Disposition'] = `attachment; filename*=UTF-8''${encodeURIComponent(safeDownloadName(file.name)).replace(/['()*]/g, c => '%' + c.charCodeAt(0).toString(16))}`;
        if (range.partial) headers['Content-Range'] = `bytes ${range.start}-${range.end}/${file.size}`;
        if (req.method === 'HEAD') { res.writeHead(range.partial ? 206 : 200, headers); res.end(); return; }
        if ([...streams.values()].filter(r => r.roomId === room.id).length >= LIMITS.concurrentStreams) fail(429, 'Too many simultaneous streams. Try again shortly.');
        streams.set(res, g); res.once('close', () => streams.delete(res));
        for (let start = range.start; start <= range.end; start += CHUNK_BYTES) {
          if (res.destroyed) break;
          if (!grants.has(url.searchParams.get('ticket'))) fail(410, 'Sharing stopped.');
          const bytes = await requestChunk(g, file, start, Math.min(start + CHUNK_BYTES - 1, range.end), res);
          if (!res.headersSent) res.writeHead(range.partial ? 206 : 200, headers);
          if (!res.write(bytes)) await once(res, 'drain', { signal: AbortSignal.timeout(readTimeout) });
        }
        res.end(); return;
      }
      const token = req.headers.authorization?.replace(/^Bearer /, '');
      const d = [...devices.values()].find(d => d.token === token);
      if (!d) fail(401, 'Reconnect this device to continue.');
      d.seenAt = now();
      if (req.method === 'GET' && url.pathname === '/api/events') {
        const since = Number(url.searchParams.get('since') ?? -1);
        if (d.version === since) await new Promise(resolve => {
          const done = () => { clearTimeout(timer); d.waiters.delete(done); res.off('close', done); resolve(); };
          const timer = setTimeout(done, 10_000);
          d.waiters.add(done); res.once('close', done);
        });
        json(res, 200, snapshot(d)); return;
      }
      if (req.method === 'POST' && url.pathname === '/api/rooms') {
        if (d.roomId || d.pendingRoom) fail(409, 'Leave your current connection first.');
        if (rooms.size >= LIMITS.rooms) fail(503, 'Connection limit reached. End an unused connection first.');
        let code;
        do { code = String(randomInt(100000, 1000000)); } while ([...rooms.values()].some(r => r.code === code));
        const r = { id: randomUUID(), ownerId: d.id, code, pairExpiresAt: now() + pairTtl, expiresAt: now() + sessionTtl, members: new Set([d.id]), pending: new Set(), files: new Map() };
        rooms.set(r.id, r); d.roomId = r.id; wake(d);
        json(res, 201, snapshot(d)); return;
      }
      if (req.method === 'POST' && url.pathname === '/api/join') {
        rate(req, 'join', 10);
        if (d.roomId || d.pendingRoom) fail(409, 'Leave your current connection first.');
        const { code } = await input(req);
        const r = [...rooms.values()].find(r => r.code === code && r.pairExpiresAt > now());
        if (!r) fail(404, 'Code expired or not found. Ask for a new code.');
        if (r.members.size + r.pending.size >= 8) fail(409, 'This session is full.');
        r.pending.add(d.id); d.pendingRoom = r.id; d.pendingAt = now(); broadcast(r); wake(d);
        json(res, 202, snapshot(d)); return;
      }
      if (req.method === 'POST' && url.pathname === '/api/leave') {
        const r = rooms.get(d.roomId || d.pendingRoom);
        if (r?.ownerId === d.id) endRoom(r);
        else if (r) { r.pending.delete(d.id); removeMember(r, d.id); }
        d.pendingRoom = null; wake(d); json(res, 200, { ok: true }); return;
      }
      if (req.method === 'POST' && url.pathname.startsWith('/api/chunks/')) {
        const r = reads.get(url.pathname.slice(12));
        if (!r || r.sourceId !== d.id) fail(410, 'This request has ended.');
        const bytes = await body(req, CHUNK_BYTES);
        if (!reads.has(r.id)) fail(410, 'This request has ended.');
        if (bytes.length !== r.end - r.start + 1) { r.reject(Object.assign(new Error('Source file changed. Select it again.'), { status: 409 })); fail(400, 'Chunk length does not match.'); }
        r.resolve(bytes); json(res, 200, { ok: true }); return;
      }
      const r = activeRoom(d);
      if (req.method === 'GET' && url.pathname === '/api/diagnostics') {
        json(res, 200, { product: 'Eluno', version: '0.2.0', protocol: PROTOCOL_VERSION, encryptedLan: Boolean(securePort), devices: r.members.size, sharedItems: r.files.size, pendingReads: [...reads.values()].filter(x => x.roomId === r.id).length }); return;
      }
      if (req.method === 'DELETE' && url.pathname.startsWith('/api/members/')) {
        if (r.ownerId !== d.id) fail(403, 'Only the connection creator can remove a device.');
        const id = url.pathname.slice('/api/members/'.length);
        if (id === d.id || !r.members.has(id)) fail(400, 'Choose a connected device.');
        removeMember(r, id); json(res, 200, { ok: true }); return;
      }
      if (req.method === 'GET' && url.pathname === '/api/pairing') {
        if (r.ownerId !== d.id) fail(403, 'Only the session creator can invite devices.');
        const allowedOrigins = securePort ? lanAddresses.map(a => `https://${a}:${securePort}`) : [origin];
        const target = url.searchParams.get('origin') || allowedOrigins[0] || origin;
        if (!allowedOrigins.includes(target)) fail(400, 'Choose a local connection address.');
        const invitation = { v: PROTOCOL_VERSION, endpoints: [target, ...allowedOrigins.filter(x => x !== target)], fingerprint: options.tls?.fingerprint, code: r.code, expiresAt: r.pairExpiresAt };
        const link = securePort ? `eluno://pair?data=${Buffer.from(JSON.stringify(invitation)).toString('base64url')}` : `${target}/#join=${r.code}`;
        const qr = await QRCode.toBuffer(link, { type: 'png', width: 240, margin: 2 });
        res.writeHead(200, { 'Content-Type': 'image/png' }); res.end(qr); return;
      }
      if (req.method === 'GET' && url.pathname === '/api/addresses') {
        json(res, 200, { origins: securePort ? lanAddresses.map(a => `https://${a}:${securePort}`) : [], lan: Boolean(securePort), fingerprint: options.tls?.fingerprint || null }); return;
      }
      if (req.method === 'POST' && url.pathname === '/api/approve') {
        if (r.ownerId !== d.id) fail(403, 'Only the session creator can approve devices.');
        const { deviceId, allow } = await input(req);
        if (!r.pending.has(deviceId)) fail(404, 'Pairing request expired.');
        const peer = devices.get(deviceId); r.pending.delete(deviceId); peer.pendingRoom = null;
        if (allow === true) { r.members.add(deviceId); peer.roomId = r.id; }
        wake(peer); broadcast(r); json(res, 200, { ok: true }); return;
      }
      if (req.method === 'POST' && url.pathname === '/api/renew-code') {
        if (r.ownerId !== d.id) fail(403, 'Only the session creator can renew pairing.');
        do { r.code = String(randomInt(100000, 1000000)); } while ([...rooms.values()].some(other => other !== r && other.code === r.code));
        r.pairExpiresAt = now() + pairTtl; broadcast(r); json(res, 200, { ok: true }); return;
      }
      if (req.method === 'POST' && url.pathname === '/api/files') {
        const { files } = await input(req);
        if (!Array.isArray(files) || files.length > 50 || r.files.size + files.length > 250) fail(400, 'Select up to 50 files at a time.');
        for (const f of files) if (!f || !cleanName(f.name) || !TYPES.has(f.type) || !Number.isSafeInteger(f.size) || f.size < 1 || (f.type.startsWith('image/') && f.size > LIMITS.imageBytes)) fail(415, 'Choose a non-empty MP4, WebM, JPEG, PNG, or WebP file. Photos must be at most 50 MB.');
        const added = files.map(f => {
          const file = { id: randomUUID(), ownerId: d.id, name: f.name, type: f.type, size: f.size, allowDownload: f.allowDownload === true };
          r.files.set(file.id, file); return file;
        });
        broadcast(r); json(res, 201, { files: added }); return;
      }
      const fileMatch = /^\/api\/files\/([^/]+)(\/open)?$/.exec(url.pathname);
      if (fileMatch) {
        const file = r.files.get(fileMatch[1]);
        if (!file) fail(404, 'This item is no longer shared.');
        if (req.method === 'PATCH' && !fileMatch[2]) {
          if (file.ownerId !== d.id) fail(403, 'Only the sharing device can change access.');
          const { allowDownload } = await input(req);
          if (typeof allowDownload !== 'boolean') fail(400, 'Choose whether copies are allowed.');
          file.allowDownload = allowDownload;
          if (!allowDownload) invalidate(g => g.fileId === file.id && g.purpose === 'download');
          broadcast(r); json(res, 200, { ok: true }); return;
        }
        if (req.method === 'DELETE' && !fileMatch[2]) {
          if (file.ownerId !== d.id) fail(403, 'Only the sharing device can stop sharing this item.');
          r.files.delete(file.id); invalidate(g => g.fileId === file.id); broadcast(r); json(res, 200, { ok: true }); return;
        }
        if (req.method === 'POST' && fileMatch[2]) {
          const data = await body(req, 1024);
          let purpose = 'view';
          if (data.length) { try { purpose = JSON.parse(data.toString()).purpose || 'view'; } catch { fail(400, 'Invalid request.'); } }
          if (!['view', 'download'].includes(purpose)) fail(400, 'Unknown viewing mode.');
          if (purpose === 'download' && !file.allowDownload) fail(403, 'The sharing device has not enabled saving copies.');
          for (const [key, grant] of grants) if (grant.viewerId === d.id && grant.fileId === file.id && grant.purpose === purpose) grants.delete(key);
          const ticket = secret();
          grants.set(ticket, { roomId: r.id, sourceId: file.ownerId, viewerId: d.id, fileId: file.id, purpose, expiresAt: r.expiresAt });
          json(res, 200, { url: `/media/${file.id}?ticket=${ticket}`, type: file.type }); return;
        }
      }
      fail(404, 'Not found.');
    } catch (error) {
      if (res.headersSent) res.destroy();
      else json(res, error.status || 500, { error: error.status ? error.message : 'Eluno could not complete this request.' });
    }
  };
  const server = http.createServer(handler);
  server.requestTimeout = 30_000;
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(options.port ?? 4173, '127.0.0.1', resolve); });
  port = server.address().port;
  let tlsServer;
  if (options.lan) {
    if (!options.tls?.fingerprint) { server.close(); throw new Error('Encrypted LAN mode requires a pairing identity.'); }
    tlsServer = https.createServer({ key: options.tls.key, cert: options.tls.cert, minVersion: 'TLSv1.2' }, handler);
    tlsServer.requestTimeout = 30_000;
    try { await new Promise((resolve, reject) => { tlsServer.once('error', reject); tlsServer.listen(options.securePort ?? 0, '0.0.0.0', resolve); }); }
    catch (error) { server.close(); throw error; }
    securePort = tlsServer.address().port;
    if (options.discovery !== false) stopAdvertising = advertise({ port: securePort, addresses: lanAddresses, onWarning: options.onDiscoveryWarning });
  }
  const timer = setInterval(sweep, 1000); timer.unref();
  return {
    server, tlsServer, port, securePort, url: `http://127.0.0.1:${port}`,
    close: async () => { clearInterval(timer); stopAdvertising?.(); for (const r of [...rooms.values()]) endRoom(r); for (const d of devices.values()) for (const done of [...d.waiters]) done(); await Promise.all([server, tlsServer].filter(Boolean).map(s => { s.closeAllConnections(); return new Promise(resolve => s.close(resolve)); })); },
    metrics: () => ({ pendingReads: reads.size, grants: grants.size, activeStreams: streams.size, maxChunkBytes: CHUNK_BYTES })
  };
}
