import test from 'node:test';
import assert from 'node:assert/strict';
import https from 'node:https';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { createElunoServer } from '../packages/core/server.mjs';
import { loadIdentity } from '../packages/core/tls.mjs';
import { safeDownloadName, LIMITS } from '../packages/protocol/index.mjs';

async function setup(t, options = {}) {
  const app = await createElunoServer({ port: 0, discovery: false, ...options }); t.after(() => app.close());
  const call = (route, who, method = 'GET', data) => fetch(app.url + route, { method, headers: who ? { Authorization: `Bearer ${who.token}` } : {}, body: data === undefined ? undefined : JSON.stringify(data) });
  const owner = await (await call('/api/devices', null, 'POST', { name: 'Creator' })).json();
  const peer = await (await call('/api/devices', null, 'POST', { name: 'Receiver' })).json();
  const { room } = await (await call('/api/rooms', owner, 'POST')).json();
  await call('/api/join', peer, 'POST', { code: room.code }); await call('/api/approve', owner, 'POST', { deviceId: peer.id, allow: true });
  const { files: [file] } = await (await call('/api/files', owner, 'POST', { files: [{ name: 'sample.png', type: 'image/png', size: 20 }] })).json();
  return { app, call, owner, peer, file };
}
test('saving copies is explicit, owner controlled, and revocable without revoking viewing', async t => {
  const { call, owner, peer, file } = await setup(t), route = `/api/files/${file.id}`;
  assert.equal((await call(route + '/open', peer, 'POST', { purpose: 'download' })).status, 403);
  assert.equal((await call(route, peer, 'PATCH', { allowDownload: true })).status, 403);
  assert.equal((await call(route, owner, 'PATCH', { allowDownload: true })).status, 200);
  const download = await (await call(route + '/open', peer, 'POST', { purpose: 'download' })).json();
  const view = await (await call(route + '/open', peer, 'POST')).json();
  assert.match((await call(download.url, null, 'HEAD')).headers.get('content-disposition'), /^attachment;/);
  await call(route, owner, 'PATCH', { allowDownload: false });
  assert.equal((await call(download.url, null, 'HEAD')).status, 410);
  assert.equal((await call(view.url, null, 'HEAD')).status, 200);
});
test('removing a device revokes existing tickets and clears its membership', async t => {
  const { call, owner, peer, file } = await setup(t);
  const grant = await (await call(`/api/files/${file.id}/open`, peer, 'POST')).json();
  assert.equal((await call('/api/members/' + owner.id, peer, 'DELETE')).status, 403);
  assert.equal((await call('/api/members/' + peer.id, owner, 'DELETE')).status, 200);
  assert.equal((await call(grant.url, null, 'HEAD')).status, 410);
  assert.equal((await (await call('/api/events', peer)).json()).room, null);
});
test('malformed metadata is rejected and diagnostics contain no connection secrets', async t => {
  const { call, owner } = await setup(t);
  for (const invalid of [null, [], 'name']) assert.equal((await call('/api/devices', null, 'POST', invalid)).status, 400);
  assert.equal((await call('/api/files', owner, 'POST', { files: [null] })).status, 415);
  assert.equal((await call('/api/files', owner, 'POST', { files: [{ name: 'large.png', type: 'image/png', size: LIMITS.imageBytes + 1 }] })).status, 415);
  const report = await (await call('/api/diagnostics', owner)).json();
  assert.deepEqual(Object.keys(report).sort(), ['devices', 'encryptedLan', 'pendingReads', 'product', 'protocol', 'sharedItems', 'version']);
  assert.equal(safeDownloadName('../bad:name\n.png'), '.._bad_name_.png');
});
test('stream concurrency is bounded and cancelled viewers release queued reads', async t => {
  const { app, call, peer, file } = await setup(t, { readTimeout: 5000 });
  const { url } = await (await call(`/api/files/${file.id}/open`, peer, 'POST')).json();
  const controls = Array.from({ length: LIMITS.concurrentStreams }, () => new AbortController());
  const pending = controls.map(controller => fetch(app.url + url, { signal: controller.signal }).catch(() => null));
  for (let i = 0; i < 100 && app.metrics().activeStreams < LIMITS.concurrentStreams; i++) await new Promise(resolve => setTimeout(resolve, 5));
  assert.equal(app.metrics().activeStreams, LIMITS.concurrentStreams);
  assert.equal((await call(url)).status, 429);
  controls.forEach(controller => controller.abort()); await Promise.all(pending);
  for (let i = 0; i < 100 && app.metrics().pendingReads; i++) await new Promise(resolve => setTimeout(resolve, 5));
  assert.equal(app.metrics().pendingReads, 0);
});
test('LAN uses TLS, persistent identity, and rejects an incorrect certificate pin', async t => {
  const directory = await mkdtemp(path.join(tmpdir(), 'eluno-test-')); t.after(() => rm(directory, { recursive: true, force: true }));
  const identity = await loadIdentity(directory);
  assert.equal((await loadIdentity(directory)).fingerprint, identity.fingerprint);
  const { app, call, owner } = await setup(t, { lan: true, tls: identity });
  assert.equal(app.server.address().address, '127.0.0.1');
  function request(pin) { return new Promise((resolve, reject) => {
    const req = https.get(`https://127.0.0.1:${app.securePort}/api/health`, { ca: identity.cert, agent: false, checkServerIdentity: (_host, cert) => createHash('sha256').update(cert.raw).digest('hex') === pin ? undefined : new Error('Certificate pin mismatch') }, res => { let text = ''; res.on('data', chunk => text += chunk); res.on('end', () => resolve(JSON.parse(text))); }); req.on('error', reject);
  }); }
  assert.equal((await request(identity.fingerprint)).lan, true);
  await assert.rejects(request('0'.repeat(64)), /pin mismatch/);
  const addresses = await (await call('/api/addresses', owner)).json();
  assert.equal(addresses.fingerprint, identity.fingerprint);
  assert.ok(addresses.origins.every(origin => origin.startsWith('https://')));
});
