import mdns from 'multicast-dns';
import { randomUUID } from 'node:crypto';
import { performance } from 'node:perf_hooks';
import { once } from 'node:events';

// Disposable same-computer DNS-SD experiment. No invitations, credentials,
// filesystem paths, or user device names are advertised.
const interfaceAddress = process.env.ELUNO_DISCOVERY_INTERFACE || '127.0.0.1';
const id = randomUUID().slice(0, 8);
const service = '_eluno-probe._tcp.local';
const instance = `Eluno-feasibility-${id}.${service}`;
const target = `eluno-probe-${id}.local`;
const advertiser = mdns({ interface: interfaceAddress, bind: '0.0.0.0', loopback: true });
const browser = mdns({ interface: interfaceAddress, bind: '0.0.0.0', loopback: true });
const warnings = [];
for (const socket of [advertiser, browser]) socket.on('warning', e => warnings.push(e.code || e.message));
let timer, interval;
try {
  const failure = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error('Discovery response not received within five seconds. Check interface, firewall, and multicast support.')), 5000);
    for (const socket of [advertiser, browser]) socket.on('error', reject);
  });
  await Promise.race([Promise.all([once(advertiser, 'ready'), once(browser, 'ready')]), failure]);
  advertiser.on('query', packet => {
    if (!packet.questions.some(q => q.name === service)) return;
    advertiser.respond({ answers: [
      { name: service, type: 'PTR', ttl: 10, data: instance },
      { name: instance, type: 'SRV', ttl: 10, data: { port: 4173, target, priority: 0, weight: 0 } },
      { name: instance, type: 'TXT', ttl: 10, data: [Buffer.from('product=Eluno'), Buffer.from('experiment=1')] },
      { name: target, type: 'A', ttl: 10, data: interfaceAddress }
    ] });
  });
  const began = performance.now();
  const received = new Promise(resolve => browser.on('response', packet => {
    const records = [...packet.answers, ...packet.additionals];
    if (records.some(r => r.type === 'PTR' && r.name === service && r.data === instance) && records.some(r => r.type === 'SRV' && r.name === instance && r.data.port === 4173)) resolve(records);
  }));
  const query = () => browser.query([{ name: service, type: 'PTR' }]);
  query(); interval = setInterval(query, 500);
  const records = await Promise.race([received, failure]);
  console.log(JSON.stringify({ experiment: 'same-computer-mdns', passed: true, elapsedMs: Math.round(performance.now() - began), interface: interfaceAddress, recordTypes: [...new Set(records.map(r => r.type))], warnings, limitation: 'Does not establish Android discovery or router compatibility.' }, null, 2));
} catch (error) {
  console.error(JSON.stringify({ experiment: 'same-computer-mdns', passed: false, error: error.message, warnings }));
  process.exitCode = 1;
} finally {
  clearTimeout(timer); clearInterval(interval);
  await Promise.all([advertiser, browser].map(socket => new Promise(resolve => socket.destroy(resolve))));
}
