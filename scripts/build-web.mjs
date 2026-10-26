import { mkdir, cp, writeFile } from 'node:fs/promises';
import path from 'node:path';
const root = path.resolve(import.meta.dirname, '..');
await mkdir(path.join(root, 'release/web'), { recursive: true });
await cp(path.join(root, 'apps/web'), path.join(root, 'release/web'), { recursive: true });
await writeFile(path.join(root, 'release/web/DEPLOYMENT.txt'), 'Eluno web client 0.2.0\nThese assets are served by the Eluno companion on the same origin.\nThey require the /api and /media endpoints in packages/core/server.mjs.\nStatic-only hosting does not provide device connections. Use the Windows app for LAN pairing.\n');
console.log('Web assets built in release/web.');
