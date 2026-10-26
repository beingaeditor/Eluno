import { mkdir, readdir, readFile, writeFile, cp } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';
const root = path.resolve(import.meta.dirname, '..'), output = path.join(root, 'release');
await mkdir(path.join(output, 'android'), { recursive: true });
for (const [source, target] of [
  ['apps/android/app/build/outputs/apk/debug/app-debug.apk', 'android/Eluno-0.2.0-debug.apk'],
  ['apps/android/app/build/outputs/apk/release/app-release-unsigned.apk', 'android/Eluno-0.2.0-release-unsigned.apk']
]) { try { await cp(path.join(root, source), path.join(output, target)); } catch (error) { if (error.code !== 'ENOENT') throw error; } }
const files = [];
async function scan(dir) { for (const entry of await readdir(dir, { withFileTypes: true })) {
  if (entry.name === 'win-unpacked') continue;
  const file = path.join(dir, entry.name);
  if (entry.isDirectory()) await scan(file);
  else if (/\.(exe|apk|aab|zip)$/.test(file)) { const bytes = await readFile(file); files.push({ path: path.relative(output, file).replaceAll('\\', '/'), bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex') }); }
} }
await scan(output);
await writeFile(path.join(output, 'manifest.json'), JSON.stringify({ product: 'Eluno', version: '0.2.0', channel: 'internal-beta', createdAt: new Date().toISOString(), releaseGates: { physicalDeviceValidation: 'deferred', userBeta: 'pending', productionSigning: 'pending', storeDistribution: 'pending' }, files }, null, 2) + '\n');
console.log(`Release manifest: ${files.length} artifacts.`);
