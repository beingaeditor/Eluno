# Eluno for iPhone and iPad: handback

This records the work against `IOS_IMPLEMENTATION_TASK.md`. It was done on Windows, with no Swift compiler, Mac, simulator, Apple signing identity or iOS device available.

## Outcomes

| Outcome | Status | Evidence, or what closes it |
| --- | --- | --- |
| Shared regressions | **Passed** | `npm run check`, `npm test` (52 of 52) and `npm run build:web` on Node 24, Windows |
| New tests can fail | **Passed** | 12 injected faults in the server, protocol, plist, manifest and project were each caught |
| Xcode project generation | **Passed** | Regenerates byte-identically, with no dangling object references. Not yet opened in Xcode |
| Swift compiled | **Pending** | Never compiled. `bash scripts/ios-build.sh` on a Mac, or the `macos-26` job in `platform-builds.yml` |
| Swift logic tests run | **Pending** | Written, never run. `npm run test:ios` on a Mac, or the same job |
| Simulator launched | **Pending** | Launch the simulator app on an iPhone and an iPad simulator |
| Device tested | **Pending** | Section 5 of the task, using the checks below |
| Signed | **Pending** | Needs the owner's Apple Developer team. Section 4 of the task |

Expect the first compile to find something. All Swift here was checked by careful reading and a delimiter and reference check, which is not a substitute for a compiler. Two selectors in the original Share Extension also look like compile errors, listed under Build below, which suggests the handoff code hadn't been built in that state.

## What changed

The defects below were found by reading the code against the protocol and Apple's documented behaviour. None were reproduced at runtime, and none of the fixes have run on iOS.

### Pairing

- `/api/health` is checked before registering: product, protocol and chunk size. Copy actions appear only if the `transfers` module is reported.
- A declined request used to leave the app waiting forever. Declined, timed-out and unreachable requests now each end with their own message.
- Failures used to all read "Could not reach". They now distinguish a changed certificate, Local Network access, an expired code and an unreachable computer.
- Every step checks that the attempt is still current, so a cancelled or superseded attempt can't attach to a session.
- Addresses that don't answer are retried briefly, because iOS can refuse a local connection while its permission alert is still showing.
- A computer's identity is remembered only after approval, so a declined attempt saves nothing.
- A 401 or a changed certificate during a session now ends it. It used to retry forever.

### Networking

- Using a connection after it closed could crash the app, because URLSession raises an exception for a task created after invalidation. A closed connection now returns an error instead.
- Bounded reads now require a 206 with a `Content-Range` matching the request and file size. Every response read is capped, so a server that ignores the range can't exhaust memory.
- The player starts no range work after its source is removed or the viewer closes.
- A failed local read now tells the coordinator at once, so the viewer doesn't wait out a 12-second timeout.

### Transfers

These are the two defects the task named, plus related ones found in the same code.

- A completion snapshot no longer cancels the task awaiting that completion's response. Decisions now come from `TransferReconciler`, a small pure function with a unit test for each case.
- Inbox publication, coordinator acknowledgement and Photos import are tracked separately. Each job is finished exactly once.
- Photos now runs after the transfer settles, so its failure can't hold back or repeat the inbox result. A saved marker and in-flight tracking prevent accidental duplicate imports.
- A lost completion reply is settled from the coordinator's own snapshot.
- Resume checks the bytes actually on disk and truncates anything past them. A copy is published only once the file size matches exactly.
- Permission alerts and iPad resizes make the scene briefly inactive, which used to cancel transfers, including the one that asked for Photos access. Only going to the background pauses work now.
- Ended transfers now remove their whole folder, not just the partial file.

### Imports

- Oversized photos and over-long names are handled before advertising, because one bad item makes the coordinator reject the whole batch.
- Each import owns a token, so a cancelled or superseded picker callback removes only its own files and can't touch the next import.
- Cancel now stops an in-progress iCloud download, not just the copy after it.
- The prepared list shows the format actually received, such as `HEVC/AAC MOV`, read from the file's tracks. Only JPEG, PNG and H.264/AAC MP4 are described as widely playable.
- Large copies no longer build up memory, which matters most in the Share Extension's small memory limit.
- Cancelling a share removes what it queued. Staging left by an extension the system ended is cleaned after an hour.

### Interface

- In a List, automatic-style buttons in one row all fire together. Tapping Accept on a transfer would also have fired Decline and Cancel. Those rows now use a bordered style.
- Previous and Next in the photo viewer used to dismiss the viewer they had just opened. It now stays in one sheet.
- Pinch zoom now accumulates, and the whole zoomed photo can be reached by scrolling.
- Viewer errors are visible, with a Save a copy option when the sender allows it.
- Transfer rows name the other device and direction.
- Action rows stack under larger text or in narrow iPad windows.
- Status messages are no longer overwritten by every snapshot.

### Build

- Replaced two Share Extension selectors that shouldn't compile: `#selector(cancel)` resolves to a local variable, and `#selector(prepare)` is ambiguous across three methods.
- Added the standard runpath settings, an explicit scene manifest and an `ElunoTests` target. The target is built only for testing, so app builds and archives are unaffected.
- Added `C617.1` to the privacy manifest, for the file timestamp read that cleans abandoned share staging. The extension still uses no required-reason APIs.

## Decisions to review

- **`prototype/test/server.test.mjs`:** this test was already failing before this work. It expected a 415 for an SVG, but `server.mjs` in this working tree deliberately accepts any file as copy-only. I rewrote that assertion to check the security property instead: the file is stored as `application/octet-stream` and can't be opened for viewing. If rejecting those types was the intent, the server is what needs changing.
- **Accept and add to Photos:** the task names explicit Photos import, and `receive(photos:)` existed but nothing called it. I added this button for media offers. Accept into inbox stays first.
- **Single window on iPad:** `UIApplicationSupportsMultipleScenes` is `false`, because one store backs the app and two windows would share its sheets. Resizing and split view still work.
- **No server changes:** everything uses the existing protocol. `/api/health` was already public, and a repeated `complete` already returned 409.

## Device checks to prioritize

Pairing depends on the first check, so run it before anything else.

1. **Pinned self-signed certificate on iOS 16 and a recent iOS.** The desktop certificate is `cA:false` with no SAN. Apple documents `NSAllowsLocalNetworking` as covering IP addresses on iOS 17 and later, and iOS 16 allows them by default, so the plist is unchanged. Apple also says ATS can't be used to loosen trust evaluation, so only a device can confirm this combination. If it fails, the documented narrower alternative is `NSExceptionDomains` with CIDR ranges on iOS 17 and later, though Apple doesn't say which sub-keys apply to IP entries.
2. **Local Network allow and deny.** The simulator doesn't implement this permission, so it needs hardware. The error text assumes denial shows up as `notConnectedToInternet`. Apple documents no specific URLSession code, so check what appears on both OS versions.
3. **Transfers in both directions**, comparing SHA-256 for each direction: pause, background, Wi-Fi loss, low space, sender cancel and revoked access.
4. **Photos:** denied permission, an unsupported format such as WebM, and a repeated Save to Photos.
5. **HEIC, HEVC and MOV originals, and compatible mode.** Compare the format label with what the file really is.
6. **Share Extension on a signed build**, including App Group access and Cancel.
7. **Layout:** iPad split view and resizing, largest accessibility text, and VoiceOver.

The simulator has no camera, so pair there with a deep link from a live invitation:

```bash
xcrun simctl openurl booted "eluno://pair?data=..."
```

Keep invitation payloads and media tickets out of logs and screenshots.

## Commands that close the pending gates

Run from the repo root on a Mac with full Xcode selected:

```bash
npm run project:ios
```

```bash
bash scripts/ios-build.sh
```

```bash
npm run test:ios
```

The `macos-26` workflow job runs the same generation, build and test steps on a pull request that touches `apps/ios/**`.
