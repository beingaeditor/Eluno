// Generate the checked-in Xcode project without requiring third-party project tools.
import { readdir, mkdir, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';
const root = path.resolve(import.meta.dirname, '../apps/ios');
const id = name => createHash('sha256').update(name).digest('hex').slice(0, 24).toUpperCase();
const quote = value => JSON.stringify(value);
const sources = (await readdir(path.join(root, 'Eluno'))).filter(f => f.endsWith('.swift')).sort();
const testSources = (await readdir(path.join(root, 'ElunoTests'))).filter(f => f.endsWith('.swift')).sort();
// Foundation-only app sources. The tests compile them directly, so they need no host app or signing.
const testedSources = ['Protocol.swift', 'TransferLogic.swift'];
const objects = [];
const add = (key, value) => objects.push(`${id(key)} = { ${value} };`);
for (const file of sources) {
  add(file, `isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ${quote(file)}; sourceTree = "<group>";`);
  add('build:' + file, `isa = PBXBuildFile; fileRef = ${id(file)};`);
}
add('assets', 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>";');
add('assets-build', `isa = PBXBuildFile; fileRef = ${id('assets')};`);
add('privacy', 'isa = PBXFileReference; lastKnownFileType = text.xml; path = PrivacyInfo.xcprivacy; sourceTree = "<group>";');
add('privacy-build', `isa = PBXBuildFile; fileRef = ${id('privacy')};`);
add('app', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = Eluno.app; sourceTree = BUILT_PRODUCTS_DIR;');
add('root', `isa = PBXGroup; children = (${id('source')}, ${id('extension-group')}, ${id('tests-group')}, ${id('products')}); sourceTree = "<group>";`);
add('source', `isa = PBXGroup; path = Eluno; sourceTree = "<group>"; children = (${sources.map(id).join(',')},${id('assets')},${id('privacy')});`);
add('products', `isa = PBXGroup; name = Products; sourceTree = "<group>"; children = (${id('app')},${id('extension-product')},${id('tests-product')});`);
add('sources', `isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (${sources.map(f => id('build:' + f)).join(',')}); runOnlyForDeploymentPostprocessing = 0;`);
add('resources', `isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (${id('assets-build')},${id('privacy-build')}); runOnlyForDeploymentPostprocessing = 0;`);
add('frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;');
for (const kind of ['project', 'target', 'extension', 'tests']) {
  for (const configuration of ['Debug', 'Release']) {
    const settings = kind === 'project' ? { SDKROOT: 'iphoneos', IPHONEOS_DEPLOYMENT_TARGET: '16.0', CLANG_ENABLE_MODULES: 'YES', SWIFT_VERSION: '5.0', SWIFT_OPTIMIZATION_LEVEL: configuration === 'Debug' ? '-Onone' : '-O' } : {
      PRODUCT_NAME: 'Eluno', PRODUCT_BUNDLE_IDENTIFIER: 'app.eluno.mobile', INFOPLIST_FILE: 'Eluno/Info.plist', GENERATE_INFOPLIST_FILE: 'NO', TARGETED_DEVICE_FAMILY: '1,2', SUPPORTED_PLATFORMS: 'iphoneos iphonesimulator', SUPPORTS_MACCATALYST: 'NO', CODE_SIGN_STYLE: 'Automatic', MARKETING_VERSION: '0.3.0', CURRENT_PROJECT_VERSION: '3', ASSETCATALOG_COMPILER_APPICON_NAME: 'AppIcon', ENABLE_USER_SCRIPT_SANDBOXING: 'YES', LD_RUNPATH_SEARCH_PATHS: '$(inherited) @executable_path/Frameworks'
    };
    if (kind === 'target') settings.CODE_SIGN_ENTITLEMENTS = 'Eluno/Eluno.entitlements';
    if (kind === 'extension') {
      Object.assign(settings, { PRODUCT_NAME: 'ElunoShare', PRODUCT_BUNDLE_IDENTIFIER: 'app.eluno.mobile.share', INFOPLIST_FILE: 'ShareExtension/Info.plist', CODE_SIGN_ENTITLEMENTS: 'ShareExtension/Share.entitlements', APPLICATION_EXTENSION_API_ONLY: 'YES', SKIP_INSTALL: 'YES', LD_RUNPATH_SEARCH_PATHS: '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks' });
      delete settings.ASSETCATALOG_COMPILER_APPICON_NAME;
    }
    if (kind === 'tests') {
      Object.assign(settings, { PRODUCT_NAME: 'ElunoTests', PRODUCT_BUNDLE_IDENTIFIER: 'app.eluno.mobile.tests', GENERATE_INFOPLIST_FILE: 'YES', LD_RUNPATH_SEARCH_PATHS: '$(inherited) @executable_path/Frameworks @loader_path/Frameworks' });
      delete settings.INFOPLIST_FILE;
      delete settings.ASSETCATALOG_COMPILER_APPICON_NAME;
    }
    add(kind + configuration, `isa = XCBuildConfiguration; name = ${configuration}; buildSettings = { ${Object.entries(settings).map(([k, v]) => `${k} = ${quote(v)};`).join(' ')} };`);
  }
  add(kind + 'config', `isa = XCConfigurationList; buildConfigurations = (${id(kind + 'Debug')},${id(kind + 'Release')}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;`);
}
add('extension-group', `isa = PBXGroup; path = ShareExtension; sourceTree = "<group>"; children = (${id('extension-source')});`);
add('extension-source', 'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ShareViewController.swift; sourceTree = "<group>";');
add('extension-build', `isa = PBXBuildFile; fileRef = ${id('extension-source')};`);
add('extension-sources', `isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (${id('extension-build')}); runOnlyForDeploymentPostprocessing = 0;`);
add('extension-product', 'isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; path = ElunoShare.appex; sourceTree = BUILT_PRODUCTS_DIR;');
add('extension', `isa = PBXNativeTarget; name = ElunoShare; productName = ElunoShare; productType = "com.apple.product-type.app-extension"; productReference = ${id('extension-product')}; buildConfigurationList = ${id('extensionconfig')}; buildPhases = (${id('extension-sources')}); dependencies = (); buildRules = ();`);
add('extension-embed', `isa = PBXBuildFile; fileRef = ${id('extension-product')}; settings = { ATTRIBUTES = (RemoveHeadersOnCopy); };`);
add('embed', `isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = (${id('extension-embed')}); name = "Embed App Extensions"; runOnlyForDeploymentPostprocessing = 0;`);
add('extension-proxy', `isa = PBXContainerItemProxy; containerPortal = ${id('project')}; proxyType = 1; remoteGlobalIDString = ${id('extension')}; remoteInfo = ElunoShare;`);
add('extension-dependency', `isa = PBXTargetDependency; target = ${id('extension')}; targetProxy = ${id('extension-proxy')};`);
add('target', `isa = PBXNativeTarget; name = Eluno; productName = Eluno; productType = "com.apple.product-type.application"; productReference = ${id('app')}; buildConfigurationList = ${id('targetconfig')}; buildPhases = (${id('sources')},${id('frameworks')},${id('resources')},${id('embed')}); dependencies = (${id('extension-dependency')}); buildRules = ();`);
for (const file of testSources) {
  add('tests:' + file, `isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ${quote(file)}; sourceTree = "<group>";`);
  add('tests-build:' + file, `isa = PBXBuildFile; fileRef = ${id('tests:' + file)};`);
}
for (const file of testedSources) add('tests-tested:' + file, `isa = PBXBuildFile; fileRef = ${id(file)};`);
add('tests-group', `isa = PBXGroup; path = ElunoTests; sourceTree = "<group>"; children = (${testSources.map(f => id('tests:' + f)).join(',')});`);
add('tests-sources', `isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (${[...testSources.map(f => id('tests-build:' + f)), ...testedSources.map(f => id('tests-tested:' + f))].join(',')}); runOnlyForDeploymentPostprocessing = 0;`);
add('tests-product', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = ElunoTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;');
add('tests', `isa = PBXNativeTarget; name = ElunoTests; productName = ElunoTests; productType = "com.apple.product-type.bundle.unit-test"; productReference = ${id('tests-product')}; buildConfigurationList = ${id('testsconfig')}; buildPhases = (${id('tests-sources')}); dependencies = (); buildRules = ();`);
add('project', `isa = PBXProject; attributes = { LastUpgradeCheck = 1600; }; buildConfigurationList = ${id('projectconfig')}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en,Base); mainGroup = ${id('root')}; productRefGroup = ${id('products')}; projectDirPath = ""; projectRoot = ""; targets = (${id('target')},${id('extension')},${id('tests')});`);
await mkdir(path.join(root, 'Eluno.xcodeproj/xcshareddata/xcschemes'), { recursive: true });
await writeFile(path.join(root, 'Eluno.xcodeproj/project.pbxproj'), `// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n${objects.join('\n')}\n}; rootObject = ${id('project')}; }\n`);
const reference = `<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${id('target')}" BuildableName="Eluno.app" BlueprintName="Eluno" ReferencedContainer="container:Eluno.xcodeproj"/>`;
const testReference = `<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${id('tests')}" BuildableName="ElunoTests.xctest" BlueprintName="ElunoTests" ReferencedContainer="container:Eluno.xcodeproj"/>`;
await writeFile(path.join(root, 'Eluno.xcodeproj/xcshareddata/xcschemes/Eluno.xcscheme'), `<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">${reference}</BuildActionEntry><BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="NO">${testReference}</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">${testReference}</TestableReference></Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">${reference}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">${reference}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>\n`);
console.log('Generated apps/ios/Eluno.xcodeproj');
