import mdns from 'multicast-dns';
import { randomBytes } from 'node:crypto';

export function advertise({ port, addresses, onWarning = () => {} }) {
  const socket = mdns();
  const id = randomBytes(4).toString('hex');
  const service = '_eluno._tcp.local', instance = `Eluno-${id}.${service}`, target = `eluno-${id}.local`;
  const records = ttl => [
    { name: service, type: 'PTR', ttl, data: instance },
    { name: instance, type: 'SRV', ttl, data: { port, target, priority: 0, weight: 0 } },
    { name: instance, type: 'TXT', ttl, data: [Buffer.from('v=1'), Buffer.from('tls=1')] },
    ...addresses.map(address => ({ name: target, type: 'A', ttl, data: address }))
  ];
  socket.on('error', onWarning); socket.on('warning', onWarning);
  socket.on('query', packet => { if (packet.questions.some(q => [service, instance, target].includes(q.name))) socket.respond(records(60)); });
  socket.on('ready', () => socket.respond(records(60)));
  const interval = setInterval(() => socket.respond(records(60)), 30_000); interval.unref();
  return () => { clearInterval(interval); socket.respond(records(0), () => socket.destroy()); };
}
