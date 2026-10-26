import { spawn } from 'node:child_process';
import { mkdir } from 'node:fs/promises';
import path from 'node:path';
const root = path.resolve(import.meta.dirname, '..');
const executable = path.join(root, 'release/windows/win-unpacked/Eluno.exe');
const data = path.join(root, '.eluno-local/packaged-smoke');
await mkdir(data, { recursive: true });
const environment = { ...process.env, ELUNO_DATA_DIR: data };
delete environment.ELECTRON_RUN_AS_NODE;
await new Promise((resolve, reject) => {
  const child = spawn(executable, ['--smoke-test'], { cwd: root, env: environment, windowsHide: true });
  let output = '', errors = '';
  const timer = setTimeout(() => { child.kill(); reject(new Error('Packaged runtime timed out.')); }, 30000);
  child.stdout.on('data', chunk => output += chunk); child.stderr.on('data', chunk => errors += chunk);
  child.once('error', error => { clearTimeout(timer); reject(error); });
  child.once('exit', code => { clearTimeout(timer); if (code === 0 && output.includes('ELUNO_SMOKE_OK')) { console.log(output.trim()); resolve(); } else reject(new Error(`Packaged runtime failed (${code}). ${errors.slice(0, 2000)}`)); });
});
