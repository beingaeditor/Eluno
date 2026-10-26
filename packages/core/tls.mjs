import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { X509Certificate } from 'node:crypto';
import path from 'node:path';
import selfsigned from 'selfsigned';

export async function loadIdentity(directory) {
  await mkdir(directory, { recursive: true });
  const file = path.join(directory, 'identity.json');
  let identity;
  try { identity = JSON.parse(await readFile(file, 'utf8')); }
  catch (error) { if (error.code !== 'ENOENT') throw new Error('Eluno identity could not be read. Restore its data directory or explicitly reset pairing.'); }
  if (!identity) {
    const generated = await selfsigned.generate([{ name: 'commonName', value: 'Eluno local companion' }], {
      keySize: 2048, algorithm: 'sha256', notBeforeDate: new Date(Date.now() - 60_000),
      notAfterDate: new Date(Date.now() + 365 * 24 * 3600_000),
      extensions: [{ name: 'basicConstraints', cA: false }, { name: 'keyUsage', digitalSignature: true, keyEncipherment: true }, { name: 'extKeyUsage', serverAuth: true }]
    });
    identity = { key: generated.private, cert: generated.cert };
    await writeFile(file, JSON.stringify(identity), { mode: 0o600, flag: 'wx' });
  }
  const certificate = new X509Certificate(identity.cert);
  if (Date.parse(certificate.validTo) <= Date.now()) throw new Error('Eluno pairing identity expired. Reset it in the data directory and pair devices again.');
  return { ...identity, fingerprint: certificate.fingerprint256.replaceAll(':', '').toLowerCase() };
}
