# Eluno — First-release product brief

Phase 0: complete. Prepared 22 October 2026.

The user selected Windows + Android as the first platform priority. The remaining choices below are working product decisions made under the instruction to complete Phase 0; they can be revised as feasibility evidence arrives.

## Purpose and positioning

Eluno brings everyday activities together across devices. Its first module makes selected videos and photos available on another screen with a built-in player. The name, navigation, and device/session model must accommodate later capabilities without a rebrand.

Primary audience: people who can install an app and select a file but should not need to understand servers, ports, IP addresses, or localhost.

## Launch decisions

| Topic | First-release decision |
| --- | --- |
| Desktop | Windows 11, with a guided companion installation and a browser workspace |
| Mobile/tablet | Android phones and tablets first; proposed minimum Android 12, subject to real-device validation |
| Browsers | Current and previous stable Chrome/Edge on Windows; Android Chrome is a feasibility client, not a substitute for the planned Android application |
| Later platforms | iPhone/iPad, macOS, and additional browsers follow evidence and demand |
| Connection | Devices on the same local network; the Windows companion remains running during sharing |
| Discovery | Nearby discovery where supported; a QR invitation is the fallback. A six-digit code confirms pairing after the app has found the companion |
| Permissions | Request network access and selected media only when the user starts the corresponding action |
| Identity | Recognizable device names and explicit approval on the initiating device; no account required for the local MVP |
| Content ownership | Source files remain on the source device. The receiver buffers data for viewing; this does not prevent screenshots or saving already received bytes |
| Direction | Windows → Android and Android → Windows are equally important launch journeys |
| Session | One computer plus one mobile/tablet is the launch acceptance scenario. Larger groups are an experiment, not a release promise |
| Persistence | First release uses temporary sessions. Remembered trusted devices require a later explicit design and opt-in |
| Background behavior | Initial sharing contract requires the source app to stay open and the device awake. Do not advertise unattended mobile hosting |
| Format baseline | Target MP4 H.264/AAC and JPEG/PNG. WebM and WebP are useful additional candidates; codec and device testing determines support |

## In scope

- Guided Windows installation and Android onboarding.
- Connect devices through nearby discovery or QR/code pairing with approval.
- Choose individual videos/photos through the system picker.
- Show each item's source device and sharing status.
- Play/pause/seek videos, control audio, and use fullscreen.
- Browse photos, move between them, zoom, and handle screen rotation.
- Stop sharing an item, disconnect a device, and end a session.
- Give actionable messages for permission denial, unsupported formats, expired pairing, connection interruption, and source unavailability.

## Deferred

Internet access between different networks; cloud media storage; automatic library indexing; file-copy/download workflows; synchronization; accounts; public links; editing; live camera/screen broadcasting; casting to televisions; continuous background hosting; automatic format conversion.

These are product boundaries for the first release, not limits on Eluno's future identity.

## Primary journeys

### Connect devices

Open Eluno on Windows → choose Connect device → open Android app → select the nearby computer or scan its QR code → compare the pairing information → approve on Windows → both screens show Connected.

If permission is denied, explain why Eluno needs it and offer Try again or Open settings as appropriate. If discovery fails, offer the QR path. If pairing expires, create a new invitation and return to the same step.

### View computer content on Android

On Windows choose Add media → select files → see the selected items with the computer's name → on Android choose an item → play or view in Eluno → close the viewer → stop sharing on Windows when finished.

Only selected items become available. Ending a share blocks new reads and tells the viewer to close the item. Bytes already received cannot be recalled.

### View Android content on the computer

While connected, on Android choose Add media → select files with the system picker → see the phone/tablet as their source → on Windows choose an item → play or view in Eluno → stop sharing on Android.

This flow must not require the person to first copy the entire file to the computer. An interruption must preserve understandable session state and allow retry when the source returns.

## Success measures

These are acceptance targets, not measured results:

- At least 4 of 5 first-time nontechnical beta participants complete pairing in 90 seconds without developer help after installation.
- Both directions pass the same video/photo acceptance checklist on each launch device.
- Target first video frame within 3 seconds and a seek within 2 seconds for a supported 1080p test file on the reference Wi-Fi network. Phase 1 hardware measurements must validate or revise these targets.
- No full-file pre-copy is required before playback. Memory used by transport must be bounded independently of video length.
- Unauthorized clients receive no media access; stopping sharing rejects subsequent reads immediately. Already buffered content is explicitly outside that guarantee.
- Common failures give a recovery action without showing server commands or requiring manually entered network addresses.
- Keyboard operation, visible focus, readable contrast, touch controls, and phone/tablet portrait/landscape layouts pass beta review.

## Product structure and naming

- Product: **Eluno**. Repository/package identifier: `eluno` where available.
- Initial destinations: **Devices**, **Shared**, and **Settings**. Future features can become separate destinations when useful.
- Use plain verbs: Connect, Approve, Add media, Play, View, Stop sharing, Disconnect.
- Keep implementation and development diagnostics outside ordinary user flows.
- Domain, trademark, and store-name availability have not been established; these are release preparation tasks, not inferred from choosing a name.

## Initial visual direction

Calm, approachable, and spacious. Warm off-white surfaces, forest-green actions, amber highlights, restrained typography, and a simple lowercase Eluno wordmark. The interface should feel useful beyond a media-player identity.

| Token | Value / usage |
| --- | --- |
| Background | `#F5F4EC` |
| Surface | `#FFFEF9` |
| Primary | `#17624C` |
| Text | `#203C32` |
| Secondary text | `#627269` |
| Accent | `#D18D46` |
| Typeface | System sans-serif; serif display accent in introductory content only |
| Controls | Clear labels, visible focus, approximately 44px primary touch controls |

## Phase 0 handoff

Screen states and recovery flows are specified in [SCREEN_FLOWS.md](SCREEN_FLOWS.md). The running feasibility interface implements onboarding, pairing, approval, shared items, viewing, stopping, and disconnection; it is not a finished production client.
