import path from 'node:path';
import { createElunoServer } from '../../packages/core/server.mjs';
import { loadIdentity } from '../../packages/core/tls.mjs';

const lan = process.argv.includes('--lan');
const tls = lan ? await loadIdentity(process.env.ELUNO_DATA_DIR || path.resolve('.eluno-local/identity')) : undefined;
const app = await createElunoServer({ port: Number(process.env.ELUNO_PORT || 4173), lan, tls });
console.log(`Eluno: ${app.url}`);
console.log(lan ? 'Encrypted Android pairing is available from Connect another device.' : 'Local web preview. Use the Windows application for automatic encrypted device connections.');
for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, async () => { await app.close(); process.exit(0); });
