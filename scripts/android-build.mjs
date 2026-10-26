import { existsSync, createWriteStream } from 'node:fs';
import { mkdir, readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { spawn } from 'node:child_process';
import { pipeline } from 'node:stream/promises';
import path from 'node:path';
import os from 'node:os';
const root = path.resolve(import.meta.dirname, '..');
const task = process.argv[2] || 'assembleDebug';
if (!['assembleDebug', 'assembleRelease', 'testDebugUnitTest', 'lintDebug', 'bundleRelease'].includes(task)) throw new Error('Unsupported Android build task.');
const home = os.homedir();
const java = process.env.JAVA_HOME || [path.join(home, '.jdks/ms-17.0.18'), 'C:/Program Files/Android/Android Studio/jbr'].find(p => existsSync(path.join(p, 'bin/java.exe')));
const sdk = process.env.ANDROID_HOME || process.env.ANDROID_SDK_ROOT || path.join(home, 'AppData/Local/Android/Sdk');
const tooling = path.join(root, '.eluno-local/tooling');
const executable = path.join(tooling, 'gradle-8.13/bin', process.platform === 'win32' ? 'gradle.bat' : 'gradle');
function run(command, args, env = process.env) { return new Promise((resolve, reject) => { const child = spawn(command, args, { cwd: root, env, stdio: 'inherit', windowsHide: true }); child.once('error', reject); child.once('exit', code => code === 0 ? resolve() : reject(new Error(`Build command failed (${code}).`))); }); }
if (!existsSync(executable)) {
  await mkdir(tooling, { recursive: true });
  const archive = path.join(tooling, 'gradle-8.13-bin.zip');
  if (!existsSync(archive)) {
    const response = await fetch('https://services.gradle.org/distributions/gradle-8.13-bin.zip');
    if (!response.ok) throw new Error(`Gradle download failed (${response.status}).`);
    await pipeline(response.body, createWriteStream(archive));
  }
  const actual = createHash('sha256').update(await readFile(archive)).digest('hex');
  if (actual !== '20f1b1176237254a6fc204d8434196fa11a4cfb387567519c61556e8710aed78') throw new Error('Gradle archive checksum mismatch. Remove the incomplete archive and retry.');
  if (process.platform === 'win32') await run('powershell.exe', ['-NoProfile', '-Command', `Expand-Archive -LiteralPath '${archive.replaceAll("'", "''")}' -DestinationPath '${tooling.replaceAll("'", "''")}' -Force`]);
  else await run('unzip', ['-q', archive, '-d', tooling]);
}
const env = { ...process.env, ...(java ? { JAVA_HOME: java } : {}), ANDROID_HOME: sdk };
const javaExecutable = java ? path.join(java, 'bin', process.platform === 'win32' ? 'java.exe' : 'java') : 'java';
const launcher = path.join(tooling, 'gradle-8.13/lib/gradle-gradle-cli-main-8.13.jar');
await run(javaExecutable, ['-Xmx64m', '-Xms64m', '-Dorg.gradle.appname=gradle', '-classpath', launcher, 'org.gradle.launcher.GradleMain', '-p', path.join(root, 'apps/android'), '--no-daemon', task], env);
