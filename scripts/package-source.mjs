import { spawnSync } from 'node:child_process';
import path from 'node:path';
if (process.platform !== 'win32') throw new Error('Use a clean Git archive on other platforms; the allowlisted source packager currently targets Windows.');
const result = spawnSync('powershell.exe', ['-NoProfile', '-File', path.join(import.meta.dirname, 'package-source.ps1')], { stdio: 'inherit', windowsHide: true });
process.exit(result.status || 0);
