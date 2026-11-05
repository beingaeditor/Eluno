# Finish Eluno for iPhone and iPad

## Task for Opus

Implement and verify the existing native iPhone and iPad client for Eluno 0.3.0. A user should be able to scan the QR code on a Windows or Linux computer, get approved on the computer, then stream selected photos and videos or send and receive persistent copies in either direction. Use the existing LAN protocol and keep the desktop as the session coordinator.

Start from the current `codex/cross-platform-transfers` **working tree**, including untracked files. At handoff, the branch tip is `a2ac34e` and the iOS client, project generator, build workflow and desktop transfer dependencies are local changes. A checkout of the Git commit alone lacks those files. Use this workspace or obtain a source snapshot that includes the changes before starting. Preserve the existing Windows, Linux, Android and web work. Return the implementation as a reviewable diff with build and test evidence.

**Compatibility target** is iOS and iPadOS 16.0 or later, with one universal SwiftUI app for iPhone and iPad. Keep the deployment target at 16.0 and use availability checks for newer APIs. Build with Xcode 26 or later and the corresponding iOS SDK. The deployment target determines what devices can run the app. The SDK requirement applies when submitting to App Store Connect, including TestFlight. [Apple Xcode requirements](https://developer.apple.com/xcode/system-requirements) · [App Store Connect build requirements](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)

## 1. Establish a clean build

- Keep `apps/ios/Eluno.xcodeproj` and its shared `Eluno` scheme reproducible with `scripts/ios-project.mjs`. Make project structure, source membership, target configuration and resource changes in the generator, then regenerate both project files.
- Use the existing `Eluno` app and embedded `ElunoShare` extension. Resolve all compile, linker and embedding failures in the Debug simulator and Release device builds. Confirm both iPhone and iPad are in the app’s device family and both targets inherit the minimum OS.
- The unsigned build script lints the plists, compiles both targets, and checks the installed bundle layout for the extension and `PrivacyInfo.xcprivacy`. The Apple job in `.github/workflows/platform-builds.yml` verifies regeneration and uploads a simulator ZIP. Use the job on an iOS pull request or dispatch the workflow where it is available. Record the workflow run or local Xcode log.

Run from the repo root on a Mac with full Xcode selected and the iOS platform installed. Node.js 22+ is required for project generation. CI uses Node.js 24.

```bash
xcode-select -p
xcodebuild -version
xcodebuild -showsdks
npm run project:ios
bash scripts/ios-build.sh
```

Expect these outputs:

- Simulator app at `release/apple/simulator/Build/Products/Debug-iphonesimulator/Eluno.app`.
- Unsigned device app at `release/apple/device/Build/Products/Release-iphoneos/Eluno.app`.

Launch the simulator app on an iPhone and iPad simulator. The simulator ZIP is for simulator use. Install a signed build for physical hardware and local-network permission checks. [Apple local-network privacy technote](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)

## 2. Finish pairing and LAN playback

Start in `Protocol.swift`, `PinnedAPI.swift`, `PinnedPlayer.swift`, `ElunoStore.swift` and `DevicePickers.swift`. Use `packages/core/server.mjs` and `packages/protocol/index.mjs` as the contract. The Windows and Linux coordinators must come from the same 0.3.0 source because the 0.2.0 installers predate approved copy transfers.

- Keep v1 QR invitations, expiry, private IPv4 HTTPS origins, the exact SHA-256 leaf certificate pin, redirect refusal and explicit desktop approval. Verify `/api/health` protocol compatibility before registering and require the transfer capability before presenting copy offers. Handle invalid QR, rejected approval, timeouts, expired codes and changed pins with actionable messages. Clear failed or superseded attempts so stale responses cannot attach the app to the wrong session.
- Test the production self-signed desktop certificate on real hardware. Keep the trust check bound to the invitation’s exact host, port and certificate. Keep ATS exceptions limited to the addresses Eluno uses and verify the Local Network allow/deny flows on iOS 16 and a recent OS. If a private-IP ATS exception is needed, use the narrowest compatible Apple-supported configuration. [Apple ATS local networking settings](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking)
- Verify JPEG and PNG viewing and H.264/AAC MP4 playback with seek in both directions. For remote video keep AVPlayer routed through the pinned resource loader. Check 206 and matching `Content-Range` for bounded requests, cap response reads, and stop range work on cancellation, source removal, revocation or disconnect. Keep the server’s 256 KiB chunk limit. Test concurrent seek and source removal during playback.
- Keep iPad usable in landscape and resizable windows. Check iPhone in portrait and landscape. Verify photo zoom and rotation, larger text, VoiceOver labels and visible playback or permission errors.

## 3. Finish imports and approved copies

Use the current Photos and Files pickers, app-private staging, transfer endpoints and inbox. Complete these flows before adding any new sharing modes.

- From Photos and Files, prepare only selected files with progress and cancellation. Test an iCloud-backed item, an unavailable provider item and a cancelled selection. Validate file type and size, including the 50 MiB photo cap, before advertising items. Cancelled or superseded picker callbacks must remove only their own temporary files and must never update the next import’s state.
- Verify original HEIC/HEIF photos and HEVC or MOV video. The existing compatible Photos picker mode requests a compatible representation. Check the actual returned format before claiming compatibility and make unsupported playback recoverable through a compatible selection or an original copy. Keep the original unchanged. Require interoperable JPEG/PNG and H.264/AAC MP4 before claiming wider codec support.
- Test `Send a copy` in both directions with a named receiver, explicit acceptance and an approved destination. Accept into the inbox by default. Support Files export and explicit Photos import for compatible media. Check that permission denial, cancelled export and failed Photos import preserve the inbox copy and present the actual outcome.
- Audit `receive` and `startPoll` in `ElunoStore.swift`. Today a completion snapshot can cancel the receiver task as it awaits the completion response. A Photos write failure can also leave a saved job pending and a later resume can skip Photos because `saved` already refers to the inbox file. Reconcile server completion with local publication and track inbox and Photos results separately. Ensure retries and lost acknowledgements cannot create duplicate inbox files or duplicate Photos imports.
- Write large copies incrementally to an incomplete file and publish only after the expected byte count is committed. Pause and resume from the verified written offset while the session and source remain valid. Test low space, duplicate names, cancel/decline, app backgrounding, Wi-Fi interruption and revoked access. Clean abandoned temporary files and preserve completed copies through disconnect and relaunch. Use a fresh offer after the source or session ends.
- Keep the existing Share Extension as a local import queue. Verify that it stages only user-selected files in the App Group, cleans incomplete staging and lets users review files in Eluno before sharing. The primary Photos and Files import flows must work independently of the extension.

## 4. Prepare signing and device installation

- Confirm the owner’s Apple Developer team controls the bundle IDs `app.eluno.mobile` and `app.eluno.mobile.share` and the App Group `group.app.eluno.shared`. Register both explicit App IDs with the same group and select the same team for both targets. If identifiers need to change, update the generator, both entitlement files and both Swift App Group lookups together. Keep team configuration and signing credentials in the owner’s local Xcode or protected environment. [Apple App Groups setup](https://developer.apple.com/documentation/xcode/configuring-app-groups)
- Open `apps/ios/Eluno.xcodeproj` in Xcode. Use **Signing & Capabilities** with automatic signing for both targets and run the `Eluno` scheme on a registered iPhone and iPad. Verify the extension can open the shared container on a signed build. [Apple registered-device distribution](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices)
- For a distributable beta, select a generic iOS device, use **Product → Archive**, and validate the archive in Organizer. Check both signed products, embedded entitlements, build numbers and privacy manifests. The main app manifest declares local preferences and storage checks. Audit any new required-reason APIs in either target. Leave TestFlight upload to the account owner’s authorized release step. [Apple privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files) · [Apple archive and beta distribution](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)

## 5. Acceptance and handback

Build the coordinators from the same checkout with `npm ci` followed by `npm run package:windows` on Windows or `npm run package:linux` on Linux. For developer testing on either desktop, `npm run desktop` launches the app and its coordinator. Connect both devices to the same private network, then open **Connect another device** on the desktop to get its QR invitation.

Use a synthetic JPEG or PNG, a seekable H.264/AAC MP4, and a large copy with a known SHA-256. Record each direction separately and compare the received original-copy checksum with the source.

| Physical pairing | Check in both directions |
| --- | --- |
| Windows ↔ iPhone | Approve once, view photos, play and seek video, send and receive a copy |
| Windows ↔ iPad | Same checks, plus portrait, landscape and resized iPad windows |
| Linux ↔ iPhone | Same pairing, playback and copy checks using the Linux desktop build |
| Linux ↔ iPad | Same checks using the Linux desktop build |

Cover the oldest available supported OS and a recent OS. Report the exact OS versions exercised. Also record denied camera and Local Network permission, wrong certificate, expired QR, declined approval, source revocation, interrupted copy resume, Photos denial, and Files or Share Extension import. Keep screenshots and logs free of credentials, invitation payloads and media tickets.

Run `npm run check`, `npm test` and `npm run build:web` for shared regressions. Add targeted coverage for any security or transfer-state regression fixed during the task. Report what was compiled, simulator-launched, device-tested and signed as separate outcomes. If macOS, credentials or a hardware combination are unavailable, report the specific gate as pending with the command or check needed to close it.

Keep this work on the private LAN and within the existing desktop-coordinated session model. Treat cloud relay, sync, mobile-only sessions, and continuous background hosting as outside this implementation.
