// The server behaviour the iOS client depends on, exercised in the same sequences it uses.
// `apps/ios/ElunoTests` covers the client's own decisions, but needs a Mac to run.
import test from 'node:test';
import assert from 'node:assert/strict';
import tls from 'node:tls';
import { createHash, X509Certificate } from 'node:crypto';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createElunoServer } from '../packages/core/server.mjs';
import { loadIdentity } from '../packages/core/tls.mjs';
import { CHUNK_BYTES, LIMITS, MEDIA_TYPES, MODULES, PROTOCOL_VERSION } from '../packages/protocol/index.mjs';

async function setup(t, options = {}) {
  const app = await createElunoServer({ port: 0, discovery: false, ...options }); t.after(() => app.close());
  const call = (route, who, method = 'GET', data, headers = {}) => fetch(app.url + route, {
    method, headers: { ...(who ? { Authorization: `Bearer ${who.token}` } : {}), ...headers }, body: data === undefined ? undefined : JSON.stringify(data)
  });
  const device = async name => (await call('/api/devices', null, 'POST', { name })).json();
  const owner = await device('Windows computer'), phone = await device('iPhone');
  const { room } = await (await call('/api/rooms', owner, 'POST')).json();
  const pair = async () => {
    assert.equal((await call('/api/join', phone, 'POST', { code: room.code })).status, 202);
    assert.equal((await call('/api/approve', owner, 'POST', { deviceId: phone.id, allow: true })).status, 200);
  };
  const state = async who => (await call('/api/events?since=-1', who)).json();
  const share = async (size = 1000, type = 'video/mp4', name = 'clip.mp4', who = owner) => (await (await call('/api/files', who, 'POST', { files: [{ name, type, size }] })).json()).files[0];
  const patch = (id, action, extra = {}) => call(`/api/transfers/${id}`, phone, 'PATCH', { action, ...extra });
  const offer = async file => (await (await call('/api/transfers', owner, 'POST', { fileId: file.id, receiverId: phone.id })).json());
  const statusOf = async id => (await state(phone)).room.transfers.find(item => item.id === id).status;
  return { app, call, owner, phone, room, pair, state, share, patch, offer, statusOf };
}

// Answers the coordinator's read requests the way a sharing device does.
function answerReads(t, f, who, respond) {
  const control = new AbortController();
  t.after(() => control.abort());
  void (async () => {
    let version = -1;
    while (!control.signal.aborted) {
      const response = await fetch(`${f.app.url}/api/events?since=${version}`, { headers: { Authorization: `Bearer ${who.token}` }, signal: control.signal });
      if (!response.ok) return;
      const snapshot = await response.json();
      version = snapshot.version;
      await Promise.all(snapshot.reads.map(read => fetch(`${f.app.url}/api/chunks/${read.id}`, {
        method: 'POST', headers: { Authorization: `Bearer ${who.token}` }, body: respond(read), signal: control.signal
      })));
    }
  })().catch(() => {});
}

test('health reports everything the client checks before registering', async t => {
  const { call } = await setup(t);
  const health = await (await call('/api/health')).json();
  assert.equal(health.product, 'Eluno');
  assert.equal(health.protocol, 1);
  assert.equal(health.chunkBytes, 262144);
  for (const id of ['transfers', 'save-copy']) assert.equal(health.modules.find(module => module.id === id)?.version, 1, id);
});

test('the Swift protocol constants match the shared protocol package', async () => {
  const swift = await readFile(new URL('../apps/ios/Eluno/TransferLogic.swift', import.meta.url), 'utf8');
  const constant = name => Number(new RegExp(`static let ${name}(?:: \\w+)? = ([\\d_]+)`).exec(swift)?.[1].replaceAll('_', ''));
  assert.equal(constant('protocolVersion'), PROTOCOL_VERSION);
  assert.equal(constant('chunkBytes'), CHUNK_BYTES);
  assert.equal(constant('maxPhotoBytes'), LIMITS.imageBytes);
  assert.equal(constant('maxFilesPerRequest'), LIMITS.filesPerRequest);
  const media = /mediaTypes: Set<String> = \[([^\]]+)\]/.exec(swift)[1].match(/"[^"]+"/g).map(value => value.slice(1, -1));
  assert.deepEqual(media.sort(), [...MEDIA_TYPES].sort());
  for (const id of ['transfers', 'save-copy']) assert.ok(MODULES.some(module => module.id === id), id);
});

test('a declined request reads as no room and nothing pending', async t => {
  const f = await setup(t);
  await f.call('/api/join', f.phone, 'POST', { code: f.room.code });
  assert.equal((await f.state(f.phone)).pending, true);
  await f.call('/api/approve', f.owner, 'POST', { deviceId: f.phone.id, allow: false });
  const after = await f.state(f.phone);
  assert.equal(after.pending, false);
  assert.equal(after.room, null);
});

test('an unanswered request reads the same way once the coordinator drops it after a minute', async t => {
  let time = Date.now();
  const f = await setup(t, { now: () => time });
  await f.call('/api/join', f.phone, 'POST', { code: f.room.code });
  time += 59_000;
  assert.equal((await f.state(f.phone)).pending, true);
  time += 2_000;
  const after = await f.state(f.phone);
  assert.equal(after.pending, false);
  assert.equal(after.room, null);
});

test('an expired or unknown code is refused with the status the client treats as final', async t => {
  let time = Date.now();
  const f = await setup(t, { now: () => time, pairTtl: 1000 });
  time += 2000;
  assert.equal((await f.call('/api/join', f.phone, 'POST', { code: f.room.code })).status, 404);
  assert.equal((await f.call('/api/join', f.phone, 'POST', { code: '000000' })).status, 404);
});

test('a device the coordinator no longer knows gets 401, which ends the session', async t => {
  const { call } = await setup(t);
  assert.equal((await call('/api/events?since=-1', { token: 'forgotten' })).status, 401);
});

test('a lost completion reply can be settled from the snapshot without repeating completion', async t => {
  const f = await setup(t); await f.pair();
  const transfer = await f.offer(await f.share());
  assert.equal((await f.patch(transfer.id, 'accept', { bytes: 0 })).status, 200);
  assert.equal((await f.patch(transfer.id, 'progress', { bytes: 1000 })).status, 200);
  assert.equal((await f.patch(transfer.id, 'complete')).status, 200);
  // The client retries because the reply was lost. A refusal alone can't say whether the copy finished.
  assert.equal((await f.patch(transfer.id, 'complete')).status, 409);
  assert.equal(await f.statusOf(transfer.id), 'completed');
});

test('a sender cancelling after publication is distinguishable from completion', async t => {
  const f = await setup(t); await f.pair();
  const transfer = await f.offer(await f.share());
  await f.patch(transfer.id, 'accept', { bytes: 0 });
  await f.patch(transfer.id, 'progress', { bytes: 1000 });
  assert.equal((await f.call(`/api/transfers/${transfer.id}`, f.owner, 'PATCH', { action: 'cancel' })).status, 200);
  assert.equal((await f.patch(transfer.id, 'complete')).status, 409);
  assert.equal(await f.statusOf(transfer.id), 'cancelled');
});

test('a published copy can still be confirmed after a pause, using only its final offset', async t => {
  const f = await setup(t); await f.pair();
  const transfer = await f.offer(await f.share());
  await f.patch(transfer.id, 'accept', { bytes: 0 });
  await f.patch(transfer.id, 'progress', { bytes: 1000 });
  assert.equal((await f.patch(transfer.id, 'pause')).status, 200);
  assert.equal((await f.patch(transfer.id, 'resume', { bytes: 1000 })).status, 200);
  assert.equal((await f.patch(transfer.id, 'complete')).status, 200);
});

test('resuming from a stale status recovers by pausing first, as the client does', async t => {
  const f = await setup(t); await f.pair();
  const transfer = await f.offer(await f.share());
  await f.patch(transfer.id, 'accept', { bytes: 0 });
  // A pause that never arrived leaves the coordinator receiving, so the first resume is refused.
  assert.equal((await f.patch(transfer.id, 'resume', { bytes: 0 })).status, 409);
  assert.equal((await f.patch(transfer.id, 'pause')).status, 200);
  assert.equal((await f.patch(transfer.id, 'resume', { bytes: 0 })).status, 200);
});

test('completion needs every byte, and resume re-bases on the verified offset', async t => {
  const f = await setup(t); await f.pair();
  const transfer = await f.offer(await f.share());
  await f.patch(transfer.id, 'accept', { bytes: 0 });
  await f.patch(transfer.id, 'progress', { bytes: 600 });
  assert.equal((await f.patch(transfer.id, 'complete')).status, 409);
  await f.patch(transfer.id, 'pause');
  assert.equal((await (await f.patch(transfer.id, 'resume', { bytes: 400 })).json()).transfer.bytes, 400);
  assert.equal((await f.patch(transfer.id, 'progress', { bytes: 399 })).status, 400);
  assert.equal((await f.patch(transfer.id, 'progress', { bytes: 1001 })).status, 400);
});

test('pausing revokes the transfer ticket and resuming issues a new one', async t => {
  const f = await setup(t); await f.pair();
  const transfer = await f.offer(await f.share());
  const { url: first } = await (await f.patch(transfer.id, 'accept', { bytes: 0 })).json();
  assert.equal((await f.call(first, null, 'HEAD')).status, 200);
  await f.patch(transfer.id, 'pause');
  assert.equal((await f.call(first, null, 'HEAD')).status, 410);
  const { url: second } = await (await f.patch(transfer.id, 'resume', { bytes: 0 })).json();
  assert.notEqual(second, first);
  assert.equal((await f.call(second, null, 'HEAD')).status, 200);
});

test('bounded reads are 206 with a matching Content-Range, including the two-byte probe', async t => {
  const f = await setup(t); await f.pair();
  const size = CHUNK_BYTES + 100;
  const file = await f.share(size);
  answerReads(t, f, f.owner, read => Buffer.alloc(read.end - read.start + 1, 1));
  const { url } = await (await f.call(`/api/files/${file.id}/open`, f.phone, 'POST')).json();
  for (const [start, end] of [[0, 1], [0, CHUNK_BYTES - 1], [CHUNK_BYTES, size - 1]]) {
    const response = await f.call(url, null, 'GET', undefined, { Range: `bytes=${start}-${end}` });
    assert.equal(response.status, 206);
    assert.equal(response.headers.get('content-range'), `bytes ${start}-${end}/${size}`);
    assert.equal((await response.arrayBuffer()).byteLength, end - start + 1);
  }
});

test('the source sees reads of at most one chunk, whatever the viewer asks for', async t => {
  const f = await setup(t); await f.pair();
  const size = CHUNK_BYTES * 2 + 5;
  const file = await f.share(size);
  const seen = [];
  answerReads(t, f, f.owner, read => { seen.push(read.end - read.start + 1); return Buffer.alloc(read.end - read.start + 1); });
  const { url } = await (await f.call(`/api/files/${file.id}/open`, f.phone, 'POST')).json();
  assert.equal((await (await f.call(url)).arrayBuffer()).byteLength, size);
  assert.ok(seen.length >= 3 && seen.every(length => length <= CHUNK_BYTES), String(seen));
});

test('an empty chunk reply fails the read now, instead of after the viewer timeout', async t => {
  const f = await setup(t, { readTimeout: 10_000 }); await f.pair();
  const file = await f.share();
  answerReads(t, f, f.owner, () => Buffer.alloc(0));
  const { url } = await (await f.call(`/api/files/${file.id}/open`, f.phone, 'POST')).json();
  const started = Date.now();
  assert.equal((await f.call(url, null, 'GET', undefined, { Range: 'bytes=0-9' })).status, 409);
  assert.ok(Date.now() - started < 5000);
});

test('a late answer to a finished read gets 410, which the client ignores', async t => {
  const f = await setup(t); await f.pair();
  assert.equal((await f.call('/api/chunks/finished-read', f.owner, 'POST', {})).status, 410);
});

test('removing a source revokes playback and cancels its transfers', async t => {
  const f = await setup(t); await f.pair();
  const file = await f.share();
  const { url } = await (await f.call(`/api/files/${file.id}/open`, f.phone, 'POST')).json();
  const transfer = await f.offer(file);
  await f.patch(transfer.id, 'accept', { bytes: 0 });
  assert.equal((await f.call(`/api/files/${file.id}`, f.owner, 'DELETE')).status, 200);
  assert.equal((await f.call(url, null, 'HEAD')).status, 410);
  const after = await f.state(f.phone);
  assert.equal(after.room.files.length, 0);
  assert.equal(after.room.transfers[0].status, 'cancelled');
  assert.equal((await f.patch(transfer.id, 'resume', { bytes: 0 })).status, 409);
});

test('revoking a member ends its room and cancels what it was receiving', async t => {
  const f = await setup(t); await f.pair();
  const transfer = await f.offer(await f.share());
  const { url } = await (await f.patch(transfer.id, 'accept', { bytes: 0 })).json();
  assert.equal((await f.call(`/api/members/${f.phone.id}`, f.owner, 'DELETE')).status, 200);
  assert.equal((await f.state(f.phone)).room, null);
  assert.equal((await f.call(url, null, 'HEAD')).status, 410);
  assert.equal((await f.state(f.owner)).room.transfers[0].status, 'cancelled');
});

test('one oversized photo rejects its whole batch, which is why the client checks first', async t => {
  const f = await setup(t); await f.pair();
  const files = sizes => f.call('/api/files', f.owner, 'POST', { files: sizes.map((size, index) => ({ name: `${index}.png`, type: 'image/png', size })) });
  assert.equal((await files([LIMITS.imageBytes])).status, 201);
  assert.equal((await files([10, LIMITS.imageBytes + 1])).status, 415);
  assert.equal((await f.state(f.owner)).room.files.length, 1);
});

test('names over 120 units reject the batch, which is why the client shortens them', async t => {
  const f = await setup(t); await f.pair();
  const named = name => f.call('/api/files', f.owner, 'POST', { files: [{ name, type: 'video/mp4', size: 10 }] });
  assert.equal((await named('a'.repeat(120))).status, 201);
  assert.notEqual((await named('a'.repeat(121))).status, 201);
});

test('a file of any other type travels as a copy but cannot be opened for viewing', async t => {
  const f = await setup(t); await f.pair();
  const file = await f.share(1000, 'application/zip', 'archive.zip');
  assert.equal(file.type, 'application/octet-stream');
  assert.equal((await f.call(`/api/files/${file.id}/open`, f.phone, 'POST')).status, 415);
  assert.equal((await f.call('/api/transfers', f.owner, 'POST', { fileId: file.id, receiverId: f.phone.id })).status, 201);
});

test('the desktop identity is what the client pins and App Transport Security expects', async t => {
  const directory = await mkdtemp(path.join(tmpdir(), 'eluno-ios-')); t.after(() => rm(directory, { recursive: true, force: true }));
  const identity = await loadIdentity(directory);
  const certificate = new X509Certificate(identity.cert);
  // The client hashes the DER leaf and compares lowercase hex, and invitations must carry that exact form.
  assert.match(identity.fingerprint, /^[a-f0-9]{64}$/);
  assert.equal(createHash('sha256').update(certificate.raw).digest('hex'), identity.fingerprint);
  assert.ok(certificate.publicKey.asymmetricKeyDetails.modulusLength >= 2048);
  const app = await createElunoServer({ port: 0, discovery: false, lan: true, tls: identity }); t.after(() => app.close());
  const session = await new Promise((resolve, reject) => {
    const socket = tls.connect({ host: '127.0.0.1', port: app.securePort, rejectUnauthorized: false }, () => resolve(socket));
    socket.once('error', reject);
  });
  t.after(() => session.destroy());
  assert.match(session.getProtocol(), /^TLSv1\.[23]$/);
  // TLS 1.3 is always forward secret. TLS 1.2 needs an ephemeral key exchange.
  assert.ok(session.getProtocol() === 'TLSv1.3' || /ECDHE/.test(session.getCipher().standardName));
});
