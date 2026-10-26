import test from 'node:test';
import assert from 'node:assert/strict';
import { performance } from 'node:perf_hooks';
import http from 'node:http';
import { createElunoServer, CHUNK_BYTES, parseRange } from '../server.mjs';

async function setup(t, options = {}) {
  const app = await createElunoServer({ port: 0, ...options });
  t.after(() => app.close());
  async function call(path, who, method = 'GET', data, extra = {}) {
    const headers = { ...(who ? { Authorization: `Bearer ${who.token}` } : {}), ...(data ? { 'Content-Type': 'application/json' } : {}), ...extra.headers };
    return fetch(app.url + path, { ...extra, method, headers, body: data ? JSON.stringify(data) : extra.body });
  }
  async function device(name) { const res = await call('/api/devices', null, 'POST', { name }); assert.equal(res.status, 201); return res.json(); }
  const owner = await device('Windows test client'), peer = await device('Android-labelled protocol client');
  const roomResponse = await call('/api/rooms', owner, 'POST');
  const room = (await roomResponse.json()).room;
  async function pair() {
    assert.equal((await call('/api/join', peer, 'POST', { code: room.code })).status, 202);
    assert.equal((await call('/api/approve', owner, 'POST', { deviceId: peer.id, allow: true })).status, 200);
  }
  async function share(who, size = 1000, type = 'video/mp4') {
    const response = await call('/api/files', who, 'POST', { files: [{ name: type.startsWith('image') ? 'test.png' : 'test.mp4', type, size }] });
    assert.equal(response.status, 201); return (await response.json()).files[0];
  }
  async function open(who, file) {
    const response = await call(`/api/files/${file.id}/open`, who, 'POST'); assert.equal(response.status, 200); return (await response.json()).url;
  }
  function source(who, generate) {
    const control = new AbortController(), observed = [];
    t.after(() => control.abort());
    const promise = (async () => {
      let version = -1;
      while (!control.signal.aborted) {
        try {
          const response = await call('/api/events?since=' + version, who, 'GET', undefined, { signal: control.signal });
          if (!response.ok) break;
          const state = await response.json(); version = state.version;
          await Promise.all(state.reads.map(async read => {
            observed.push(read);
            const bytes = generate(read.start, read.end);
            await call('/api/chunks/' + read.id, who, 'POST', undefined, { body: bytes, signal: control.signal });
          }));
        } catch (error) { if (!control.signal.aborted) throw error; }
      }
    })();
    promise.catch(() => {});
    return { observed, stop: async () => { control.abort(); await promise; } };
  }
  return { app, call, owner, peer, room, pair, device, share, open, source };
}

test('range parsing handles full, open-ended, suffix and invalid ranges', () => {
  assert.deepEqual(parseRange(undefined, 100), { start: 0, end: 99, partial: false });
  assert.deepEqual(parseRange('bytes=20-', 100), { start: 20, end: 99, partial: true });
  assert.deepEqual(parseRange('bytes=-10', 100), { start: 90, end: 99, partial: true });
  assert.deepEqual(parseRange('bytes=0-999', 100), { start: 0, end: 99, partial: true });
  for (const value of ['bytes=100-', 'bytes=30-20', 'bytes=-0', 'bytes=0-1,4-5', 'bytes=-', 'other=0-1']) assert.throws(() => parseRange(value, 100), { status: 416 });
});

test('pairing requires explicit approval and prevents unpaired content access', async t => {
  const f = await setup(t);
  const file = await f.share(f.owner);
  assert.equal((await f.call('/api/events', null)).status, 401);
  assert.equal((await f.call('/api/join', f.peer, 'POST', { code: f.room.code })).status, 202);
  assert.equal((await f.call(`/api/files/${file.id}/open`, f.peer, 'POST')).status, 409);
  assert.equal((await f.call('/api/approve', f.peer, 'POST', { deviceId: f.peer.id, allow: true })).status, 409);
  await f.call('/api/approve', f.owner, 'POST', { deviceId: f.peer.id, allow: true });
  assert.ok(await f.open(f.peer, file));
});

test('decline and cancellation release pairing requests', async t => {
  const f = await setup(t);
  await f.call('/api/join', f.peer, 'POST', { code: f.room.code });
  await f.call('/api/approve', f.owner, 'POST', { deviceId: f.peer.id, allow: false });
  assert.equal((await (await f.call('/api/events', f.peer)).json()).pending, false);
  await f.call('/api/join', f.peer, 'POST', { code: f.room.code });
  await f.call('/api/leave', f.peer, 'POST');
  assert.deepEqual((await (await f.call('/api/events', f.owner)).json()).room.pending, []);
});

test('streams original bytes in both directions and supports seeking', async t => {
  const f = await setup(t); await f.pair();
  const data = Buffer.alloc(CHUNK_BYTES * 2 + 7654);
  for (let i = 0; i < data.length; i++) data[i] = i % 251;
  for (const [sender, viewer] of [[f.owner, f.peer], [f.peer, f.owner]]) {
    const file = await f.share(sender, data.length);
    const source = f.source(sender, (start, end) => data.subarray(start, end + 1));
    const url = await f.open(viewer, file);
    const start = performance.now();
    const response = await f.call(url);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('accept-ranges'), 'bytes');
    assert.deepEqual(Buffer.from(await response.arrayBuffer()), data);
    const seek = await f.call(url, null, 'GET', undefined, { headers: { Range: 'bytes=270000-280000' } });
    assert.equal(seek.status, 206);
    assert.equal(seek.headers.get('content-range'), `bytes 270000-280000/${data.length}`);
    assert.deepEqual(Buffer.from(await seek.arrayBuffer()), data.subarray(270000, 280001));
    const suffix = await f.call(url, null, 'GET', undefined, { headers: { Range: 'bytes=-100' } });
    assert.deepEqual(Buffer.from(await suffix.arrayBuffer()), data.subarray(-100));
    assert.ok(source.observed.every(read => read.end - read.start + 1 <= CHUNK_BYTES));
    console.log(JSON.stringify({ experiment: sender === f.owner ? 'forward-protocol' : 'reverse-protocol', bytes: data.length, elapsedMs: Math.round(performance.now() - start), maximumRequestedChunk: Math.max(...source.observed.map(r => r.end - r.start + 1)) }));
    await source.stop();
  }
});

test('photo transport works without Range and HEAD does not read source bytes', async t => {
  const f = await setup(t); await f.pair();
  const png = Buffer.from('89504e470d0a1a0a', 'hex');
  const file = await f.share(f.owner, png.length, 'image/png');
  const url = await f.open(f.peer, file);
  const head = await f.call(url, null, 'HEAD');
  assert.equal(head.status, 200); assert.equal(head.headers.get('content-type'), 'image/png');
  assert.equal(f.app.metrics().pendingReads, 0);
  const source = f.source(f.owner, (start, end) => png.subarray(start, end + 1));
  assert.deepEqual(Buffer.from(await (await f.call(url)).arrayBuffer()), png);
  await source.stop();
});

test('a virtual 5 GiB file can be sought without full-file buffering', async t => {
  const f = await setup(t); await f.pair();
  const size = 5 * 1024 ** 3, start = size - 8192;
  const file = await f.share(f.peer, size);
  const source = f.source(f.peer, (a, b) => Buffer.alloc(b - a + 1, 77));
  const response = await f.call(await f.open(f.owner, file), null, 'GET', undefined, { headers: { Range: `bytes=${start}-` } });
  assert.equal(response.headers.get('content-range'), `bytes ${start}-${size - 1}/${size}`);
  assert.deepEqual(Buffer.from(await response.arrayBuffer()), Buffer.alloc(8192, 77));
  assert.equal(source.observed.length, 1); assert.equal(source.observed[0].start, start);
  await source.stop();
});

test('revocation blocks existing tickets and unauthorized deletion', async t => {
  const f = await setup(t); await f.pair();
  const file = await f.share(f.owner), url = await f.open(f.peer, file);
  assert.equal((await f.call(`/api/files/${file.id}`, f.peer, 'DELETE')).status, 403);
  assert.equal((await f.call(`/api/files/${file.id}`, f.owner, 'DELETE')).status, 200);
  assert.equal((await f.call(url)).status, 410);
});

test('revocation cancels an in-flight read', async t => {
  const f = await setup(t); await f.pair();
  const file = await f.share(f.owner), url = await f.open(f.peer, file);
  const pending = f.call(url);
  await new Promise(resolve => setImmediate(resolve));
  // Synchronize on the actual source request instead of relying on a fixed delay.
  let found = false;
  for (let i = 0; i < 20; i++) {
    const state = await (await f.call('/api/events', f.owner)).json();
    if (state.reads.length) { found = true; break; }
  }
  assert.ok(found);
  await f.call(`/api/files/${file.id}`, f.owner, 'DELETE');
  assert.equal((await pending).status, 410);
  assert.equal(f.app.metrics().pendingReads, 0);
});

test('leaving or ending a session invalidates media access', async t => {
  const f = await setup(t); await f.pair();
  const file = await f.share(f.owner), url = await f.open(f.peer, file);
  await f.call('/api/leave', f.peer, 'POST');
  assert.equal((await f.call(url)).status, 410);
  await f.pair();
  const again = await f.open(f.peer, file);
  await f.call('/api/leave', f.owner, 'POST');
  assert.equal((await f.call(again)).status, 410);
  assert.equal((await (await f.call('/api/events', f.peer)).json()).room, null);
});

test('expired codes, pending approvals and sessions are rejected', async t => {
  let clock = Date.now();
  const f = await setup(t, { now: () => clock, pairTtl: 1000, sessionTtl: 100_000 });
  await f.call('/api/join', f.peer, 'POST', { code: f.room.code });
  clock += 61_000;
  assert.equal((await (await f.call('/api/events', f.peer)).json()).pending, false);
  assert.equal((await f.call('/api/join', f.peer, 'POST', { code: f.room.code })).status, 404);
  assert.equal((await f.call('/api/approve', f.owner, 'POST', { deviceId: f.peer.id, allow: true })).status, 404);
  await f.call('/api/renew-code', f.owner, 'POST');
  const updated = (await (await f.call('/api/events', f.owner)).json()).room;
  assert.notEqual(updated.code, f.room.code);
  assert.equal((await f.call('/api/join', f.peer, 'POST', { code: updated.code })).status, 202);
  await f.call('/api/approve', f.owner, 'POST', { deviceId: f.peer.id, allow: true });
  clock += 40_000;
  assert.equal((await (await f.call('/api/events', f.peer)).json()).room, null);
});

test('code guesses are rate limited', async t => {
  const f = await setup(t);
  for (let i = 0; i < 10; i++) assert.equal((await f.call('/api/join', f.peer, 'POST', { code: 'invalid' })).status, 404);
  assert.equal((await f.call('/api/join', f.peer, 'POST', { code: f.room.code })).status, 429);
});

test('unsupported files, invalid byte ranges, forged hosts and cross-origin requests fail', async t => {
  const f = await setup(t); await f.pair();
  assert.equal((await f.call('/api/files', f.owner, 'POST', { files: [{ name: 'script.svg', type: 'image/svg+xml', size: 10 }] })).status, 415);
  assert.equal((await f.call('/api/rooms', f.owner, 'POST', undefined, { headers: { Origin: 'https://other.example' } })).status, 403);
  const forgedHostStatus = await new Promise((resolve, reject) => {
    http.get(f.app.url + '/api/health', { headers: { Host: 'attacker.example' } }, response => { response.resume(); resolve(response.statusCode); }).once('error', reject);
  });
  assert.equal(forgedHostStatus, 403);
  const file = await f.share(f.owner), url = await f.open(f.peer, file);
  const invalid = await f.call(url, null, 'GET', undefined, { headers: { Range: 'bytes=9000-' } });
  assert.equal(invalid.status, 416); assert.equal(invalid.headers.get('content-range'), 'bytes */1000');
  assert.equal((await f.call('/media/' + file.id + '?ticket=wrong')).status, 410);
});

test('unavailable sources time out and can recover on the same session', async t => {
  const f = await setup(t, { readTimeout: 100 }); await f.pair();
  const file = await f.share(f.owner), url = await f.open(f.peer, file);
  assert.equal((await f.call(url)).status, 504);
  const source = f.source(f.owner, (a, b) => Buffer.alloc(b - a + 1));
  const recovered = await f.call(url); assert.equal(recovered.status, 200); await recovered.arrayBuffer();
  assert.equal(f.app.metrics().pendingReads, 0); await source.stop();
});

test('QR invitations produce local PNGs and reject external destinations', async t => {
  const f = await setup(t);
  const qr = await f.call('/api/pairing', f.owner);
  assert.equal(qr.status, 200); assert.equal(qr.headers.get('content-type'), 'image/png');
  assert.deepEqual(Buffer.from(await qr.arrayBuffer()).subarray(0, 8), Buffer.from('89504e470d0a1a0a', 'hex'));
  assert.equal((await f.call('/api/pairing?origin=https://other.example', f.owner)).status, 400);
  assert.equal((await f.call('/api/pairing', f.peer)).status, 409);
});
