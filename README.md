# Eluno

Bring your devices together. Eluno shares selected videos and photos in either direction between a Windows computer and an Android phone or tablet, with an integrated player and photo viewer. Search and owner-authorized saving copies are the first optional capabilities.

**Status: 0.2.0 internal beta, under verification.** The Android app has built and 19 integration tests passed. Physical Windows ↔ Android checks were deferred by the user. Real-user beta, production signing, distribution and final browser QA remain open. The workspace folder is still named `vidlocal`; the product and packages are named Eluno.

Source repository: [beingaeditor/Eluno](https://github.com/beingaeditor/Eluno). Maintain application code, tests, documentation and CI here; keep credentials, local app data and generated build artifacts out of Git.

## For users

The Windows application starts its connection service automatically. People using it do not run server commands or enter network addresses.

1. Open Eluno on Windows and choose a device name.
2. Select **Connect another device**.
3. Open Eluno on Android, choose **Scan computer invitation**, and scan the QR code. Approve the request on Windows.
4. Add media on either screen and play or view it on the other.
5. Stop sharing an item, remove a device, or disconnect to end future access.

Use the same private Wi-Fi and keep both apps open. Android hosting pauses in the background. The computer remains the session coordinator even when the phone supplies the media. No cloud account, media upload or telemetry is used.

See the [user guide](docs/USER_GUIDE.md), [privacy information](docs/PRIVACY.md) and [device validation steps](docs/phase-1/DEVICE_VALIDATION.md).

## Codebase

| Directory | Purpose |
| --- | --- |
| `apps/web` | Browser interface, video/photo viewer, search, sharing and device controls |
| `apps/desktop` | Sandboxed Electron Windows application; starts the companion automatically |
| `apps/android` | Native Java Android 12+ phone/tablet application, QR scan, pinned TLS, Media3 playback and system file pickers |
| `apps/companion` | Developer CLI for the same connection service |
| `packages/core` | Sessions, approval, revocation, bounded range streaming, TLS identity and mDNS advertising |
| `packages/protocol` | Versioned contracts, limits, media formats and optional capability declarations |
| `tests`, `prototype/test` | Integration and security checks; historical feasibility tests retained |
| `scripts` | Repeatable builds, syntax checks and artifact checksums |
| `docs` | Product decisions, prepared acceptance tests and release process |

## Develop

Requires Node.js 22+ (24 recommended). Run from this folder:

```powershell
npm ci
npm run desktop
```

For the web interface alone, `npm start` serves a loopback preview and prints its URL. Two browser tabs can exercise both sharing directions using **Try with sample media**. `npm run start:lan` starts the encrypted LAN service for native Android development. Keep this service on a private LAN.

```powershell
npm run check
npm test
npm run build:web
npm run package:windows
npm run build:android
node scripts/android-build.mjs testDebugUnitTest
node scripts/android-build.mjs lintDebug
npm run build:android:release
npm run release:manifest
```

Android requires Java 17+, an Android SDK with platform 36 and accepted SDK licenses. The helper downloads Gradle 8.13 from its official distribution and verifies its SHA-256. Set `JAVA_HOME` and `ANDROID_HOME` when installed locations are not discovered automatically. Network access is needed on the first build. Open `apps/android` in Android Studio for native development.

Outputs go to ignored `release/`; Android build outputs remain under `apps/android/app/build/outputs`. Release signing needs the owner's credentials; see the [release procedure](docs/release/RELEASE.md). The Windows package is unsigned for internal testing; Android's debug APK uses a development signature. Neither is a published 1.0 release.

The web build is served by the companion and requires its same-origin API. Copying static assets onto an internet host does not establish LAN connections. A hosted web shell, remote relay, iOS/iPad app, continuous mobile background serving, transcoding and cloud synchronization are outside this beta.

## Security and scope

The desktop UI uses HTTP only over loopback. Android communicates over TLS and verifies the computer's exact certificate fingerprint from the invitation; no certificate-warning bypass is needed. Invitations expire after five minutes and need desktop approval. Sessions last up to eight hours. Media reads use bounded 256 KiB chunks; originals are read on demand rather than uploaded in advance. Downloads require explicit owner permission.

Anyone able to view content can retain received bytes or record their screen. Revocation ends future access and cannot erase copies already received. Photos are limited to 50 MiB; MP4/WebM codecs depend on the receiving device. See [architecture and security](docs/ARCHITECTURE.md) and the [phase plan](PROJECT_PLAN.md) for acceptance gates and limitations.
