// Checks of the iOS project that need no Mac: generation, targets, identifiers, permissions and privacy.
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readdir, readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const root = new URL('../apps/ios/', import.meta.url);
const read = name => readFile(new URL(name, root), 'utf8');
const swiftIn = async folder => Promise.all((await readdir(new URL(folder, root))).filter(name => name.endsWith('.swift')).map(name => read(`${folder}/${name}`)));

test('the checked-in Xcode project is exactly what the generator produces', async () => {
  const files = ['Eluno.xcodeproj/project.pbxproj', 'Eluno.xcodeproj/xcshareddata/xcschemes/Eluno.xcscheme'];
  const before = await Promise.all(files.map(read));
  const result = spawnSync(process.execPath, [fileURLToPath(new URL('../scripts/ios-project.mjs', import.meta.url))], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  const after = await Promise.all(files.map(read));
  // Leave the tree as it was found, so a stale project fails here and stays visible in review.
  await Promise.all(files.map((name, index) => writeFile(new URL(name, root), before[index])));
  // A Windows checkout may hold these with CRLF endings, which isn't a difference in the project.
  const normalized = contents => contents.map(text => text.replaceAll('\r\n', '\n'));
  assert.deepEqual(normalized(after), normalized(before), 'Run npm run project:ios and include the result.');
});

test('every app source is in the app target, and the tests compile only Foundation sources', async () => {
  const project = await read('Eluno.xcodeproj/project.pbxproj');
  for (const name of (await readdir(new URL('Eluno', root))).filter(file => file.endsWith('.swift'))) assert.ok(project.includes(`path = "${name}"`), name);
  for (const name of ['Protocol.swift', 'TransferLogic.swift']) {
    const source = await read(`Eluno/${name}`);
    assert.deepEqual([...source.matchAll(/^import (\w+)/gm)].map(match => match[1]), ['Foundation'], name);
  }
});

test('both products target iPhone and iPad and inherit the 16.0 minimum', async () => {
  const project = await read('Eluno.xcodeproj/project.pbxproj');
  const deployment = [...project.matchAll(/IPHONEOS_DEPLOYMENT_TARGET = "([^"]+)"/g)].map(match => match[1]);
  // One value per project configuration. A target-level override would add more.
  assert.deepEqual(deployment, ['16.0', '16.0']);
  const families = [...project.matchAll(/TARGETED_DEVICE_FAMILY = "([^"]+)"/g)].map(match => match[1]);
  assert.ok(families.length >= 4 && families.every(value => value === '1,2'), families.join());
  assert.ok(project.includes('PRODUCT_BUNDLE_IDENTIFIER = "app.eluno.mobile";'));
  assert.ok(project.includes('PRODUCT_BUNDLE_IDENTIFIER = "app.eluno.mobile.share";'));
});

test('the extension is embedded in PlugIns and the app rebuilds it', async () => {
  const project = await read('Eluno.xcodeproj/project.pbxproj');
  assert.match(project, /isa = PBXCopyFilesBuildPhase;[^}]*dstSubfolderSpec = 13;/);
  assert.match(project, /isa = PBXTargetDependency;/);
  assert.match(project, /com\.apple\.product-type\.app-extension/);
  assert.match(project, /APPLICATION_EXTENSION_API_ONLY = "YES"/);
});

test('the shared scheme builds tests only for testing, so app builds and archives stay unaffected', async () => {
  const scheme = await read('Eluno.xcodeproj/xcshareddata/xcschemes/Eluno.xcscheme');
  const entries = [...scheme.matchAll(/<BuildActionEntry ([^>]*)>\s*<BuildableReference [^>]*BuildableName="([^"]+)"/g)].map(match => [match[2], match[1]]);
  const tests = entries.find(([name]) => name === 'ElunoTests.xctest')?.[1];
  assert.match(tests, /buildForTesting="YES"/);
  for (const action of ['buildForRunning', 'buildForArchiving', 'buildForProfiling']) assert.match(tests, new RegExp(`${action}="NO"`));
  assert.match(scheme, /<TestAction [\s\S]*ElunoTests\.xctest[\s\S]*<\/TestAction>/);
});

test('the App Group matches across both entitlements and both Swift lookups', async () => {
  const group = 'group.app.eluno.shared';
  for (const name of ['Eluno/Eluno.entitlements', 'ShareExtension/Share.entitlements', 'Eluno/ElunoStore.swift', 'ShareExtension/ShareViewController.swift']) {
    assert.ok((await read(name)).includes(group), name);
  }
});

test('permissions are explained, and network exceptions stay limited to local networking', async () => {
  const plist = await read('Eluno/Info.plist');
  for (const key of ['NSCameraUsageDescription', 'NSLocalNetworkUsageDescription', 'NSPhotoLibraryAddUsageDescription']) assert.match(plist, new RegExp(`<key>${key}</key><string>[^<]+</string>`), key);
  assert.match(plist, /<key>NSAppTransportSecurity<\/key><dict><key>NSAllowsLocalNetworking<\/key><true\/><\/dict>/);
  assert.doesNotMatch(plist, /NSAllowsArbitraryLoads/);
  assert.doesNotMatch(plist, /NSExceptionAllowsInsecureHTTPLoads/);
});

test('iPad keeps every orientation, which split view and resizable windows require', async () => {
  const plist = await read('Eluno/Info.plist');
  const ipad = /UISupportedInterfaceOrientations~ipad<\/key><array>(.*?)<\/array>/.exec(plist)[1];
  for (const orientation of ['Portrait', 'PortraitUpsideDown', 'LandscapeLeft', 'LandscapeRight']) assert.ok(ipad.includes(`UIInterfaceOrientation${orientation}<`), orientation);
  assert.doesNotMatch(plist, /UIRequiresFullScreen/);
});

// Apple's required-reason API categories, by the source tokens Eluno could use to reach them.
const requiredReasons = [
  { category: 'NSPrivacyAccessedAPICategoryUserDefaults', reason: 'CA92.1', tokens: ['UserDefaults'] },
  { category: 'NSPrivacyAccessedAPICategoryDiskSpace', reason: 'E174.1', tokens: ['volumeAvailableCapacity', 'systemFreeSize', 'statfs'] },
  { category: 'NSPrivacyAccessedAPICategoryFileTimestamp', reason: 'C617.1', tokens: ['creationDate', 'contentModificationDate', 'modificationDate', 'fileModificationDate'] },
  { category: 'NSPrivacyAccessedAPICategorySystemBootTime', reason: null, tokens: ['systemUptime', 'mach_absolute_time'] },
  { category: 'NSPrivacyAccessedAPICategoryActiveKeyboards', reason: null, tokens: ['activeInputModes'] }
];

test('the privacy manifest declares each required-reason API the app uses', async () => {
  const sources = (await swiftIn('Eluno')).join('\n');
  const manifest = await read('Eluno/PrivacyInfo.xcprivacy');
  for (const { category, reason, tokens } of requiredReasons) {
    const used = tokens.filter(token => sources.includes(token));
    if (!used.length) continue;
    assert.ok(reason, `${category} is used (${used}) but has no approved reason here`);
    assert.match(manifest, new RegExp(`${category}</string>\\s*<key>NSPrivacyAccessedAPITypeReasons</key>\\s*<array>\\s*<string>${reason.replace('.', '\\.')}</string>`), category);
  }
});

test('the Share Extension uses no required-reason APIs, so it needs no manifest of its own', async () => {
  const sources = (await swiftIn('ShareExtension')).join('\n');
  for (const { tokens } of requiredReasons) for (const token of tokens) assert.ok(!sources.includes(token), token);
});

test('private staging names are the same in the extension and the app', async () => {
  assert.ok((await read('ShareExtension/ShareViewController.swift')).includes('".pending-"'));
  assert.ok((await read('Eluno/ElunoStore.swift')).includes('".pending-"'));
});
