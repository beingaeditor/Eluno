# Eluno internal beta builds and release gates

Version 0.2.0 is an engineering/internal beta. Build success does not complete hardware acceptance, a real-user beta, publication or production signing. Keep the release channel at internal-beta until the gates below are recorded.

## Build and inventory

Use a clean Node 24 environment with `npm ci`. Run `npm run check` and `npm test`. Build web assets with `npm run build:web`, the Windows x64 NSIS installer with `npm run package:windows`, and an optional portable executable with `npm run package:portable`.

Use Java 17+, SDK platform 36 and an accepted SDK license for Android. Run `node scripts/android-build.mjs testDebugUnitTest`, `node scripts/android-build.mjs lintDebug`, `npm run build:android` and `npm run build:android:release`. Gradle's official archive checksum is pinned in the helper. Debug packages use the SDK's development key; release APKs are unsigned unless explicitly configured below.

Run `npm run release:manifest` after all builds. It copies APK outputs into `release/android` and writes SHA-256 hashes and byte counts to `release/manifest.json`. Distribute only reviewed artifacts whose checksums match. Never include `.eluno-local`, signing files, app data, downloaded test media or developer caches in the source archive. `node scripts/package-source.mjs` creates an allowlisted source zip.

The Windows installer is per-user, allows choosing a location, and creates a desktop shortcut. It starts the connection service within the application, with no server setup commands for users. The portable build is intended for internal testing. The current artifacts are unsigned; they may trigger operating-system reputation checks. Signing and a trusted distribution channel are required before general consumer release.

## Signing

Android release signing reads these environment variables without printing their values: `ELUNO_ANDROID_KEYSTORE`, `ELUNO_ANDROID_STORE_PASSWORD`, `ELUNO_ANDROID_KEY_ALIAS`, `ELUNO_ANDROID_KEY_PASSWORD`. Keep the keystore outside the repository and use protected CI secrets for builds. With signing configured, the build produces `app-release.apk`; distribute that reviewed file, not a stale unsigned output. An AAB can be built with `node scripts/android-build.mjs bundleRelease` for the chosen store process.

Windows currently sets `win.signExecutable: false` for internal artifacts. For a production signing job, override it to true in a separate protected builder config and provide the code-signing certificate/approved signing service required by electron-builder. Do not commit credentials. Verify the installed executable and installer signatures and timestamp after building. No automatic updater or signing account is provisioned by this codebase; updates are manually obtained and installed from the eventual trusted distribution channel.

## Acceptance gates

| Gate | Required evidence | Current status |
| --- | --- | --- |
| Protocol/access control | Automated both-direction bytes, ranges, expiry, approval, revocation, downloads and TLS pin checks | 19 checks passed during development |
| Android build/unit/lint | Fresh APKs, unit results and reviewed lint output | Debug build and unit tests passed; lint warnings under review |
| Windows installer | Fresh machine install, launch, pairing, upgrade, uninstall, metadata/signature check | Installer build produced; installation acceptance pending |
| Final UI | Browser responsive pass, keyboard/screen reader, Android TalkBack, rotation and native playback | Final browser pass blocked by approval usage limit; device checks pending |
| Hardware | Windows ↔ Android phone and tablet on real Wi-Fi, actual large files, background and recovery | Deferred by user; prepared steps available |
| Nontechnical beta | At least five observed first-use sessions; record failure points without collecting private media | Not run |
| Privacy/security review | Check pinning, secrets, permissions, data retention, consent and support wording | Implementation and tests present; independent review pending |
| Distribution | Owner-selected signing identity, store/beta accounts, support route, release notes, rollback test | Not provisioned/published |

Suggested beta targets are provisional and must be measured: at least 9/10 successful pair attempts, first frame within five seconds for the generated small clip, seek recovery within three seconds on the supported LAN, and no monotonic memory growth after 20 view/close cycles. Do not infer these metrics from loopback throughput. Record device, network, source size, codec and direction for every measurement; revise targets from actual results.

## Update and rollback

Keep the last known-good installer and its checksum. Disconnect and close Eluno before an upgrade. Install the new version through the same per-user channel; pair again because sessions are intentionally in memory. Android updates require the same signing identity and increasing versionCode; debug and release signing identities are different.

For a failed beta, stop the new app and reinstall the known-good compatible Windows version. Android may require uninstalling a newer build to install an older version, which removes app data; saved copies outside app storage remain separate. Test this process on disposable QA devices before release. No successful rollback execution is claimed yet.

Packaged Windows identity data normally lives under `%APPDATA%\eluno` (Electron app name); inspect the actual app-data location on the installed build. Development uses `.eluno-local/desktop` and CLI LAN mode `.eluno-local/identity`, unless `ELUNO_DATA_DIR` is deliberately set. The identity expires after one year. To renew/reset it, close the app, back up its data privately if needed, remove only `identity.json`, reopen and pair again. Do not share that backup or identity file. Uninstall does not promise deletion of app data; remove app data explicitly for a complete reset.

## Hosting and operations

The current runtime is local-first and has no hosted service bill or remote monitoring. Its web assets require the companion API on the same origin. A public static host cannot reach the user's private network automatically. Internet access and a hosted web entry point require their own service/discovery design, threat review and operating budget; do not forward the companion's port publicly. Public site hosting and store submission remain owner-dependent release work.

CI in `.github/workflows/ci.yml` checks the code and creates internal artifacts when the repository exists on GitHub. It has read-only repository permissions and no deployment, signing, telemetry or publication step. The workflow has been authored locally and has not yet run on GitHub.
