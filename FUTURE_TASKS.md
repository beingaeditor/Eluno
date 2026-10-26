# Eluno — Future work

Updated: 27 October 2026. Repository: [beingaeditor/Eluno](https://github.com/beingaeditor/Eluno).

## Direction

Make Eluno a simple way to connect Windows, Linux, Android, iPhone and iPad for viewing and moving selected media. People should install the app, connect their devices, and choose what to share without starting a server or entering a network address.

**Current priority: implementation. Testing work is deferred at the user's request.** Existing test code and recorded results remain in the repository. This roadmap does not mark outstanding device or release validation as completed. All unchecked items below are future tasks, not existing features.

The current code provides Windows/Android applications, a web interface, two-way streaming, pairing/approval, search, and optional saving copies. Linux packaging, native iPhone/iPad support, and an explicit destination-based upload experience are the next additions.

## What “upload” means

Keep two clear actions:

- **Share to view:** another connected device streams selected media while the source stays available.
- **Send a copy:** media is transferred into a destination selected or approved by the receiving person, and remains available after the source disconnects.

“Uploading to iPhone/iPad” includes both sending computer media to those devices and sending selected iPhone/iPad media back to a computer. It does not imply a cloud upload or unrestricted access to an entire photo library. The existing Save copy feature is a useful starting point; a sender selecting a destination, receiver approval, and a visible transfer queue still need implementation.

## Recommended delivery order

| Order | Milestone | Why this comes next |
| --- | --- | --- |
| 1 | Linux desktop support | Reuse the existing desktop/core code and provide another computer that can coordinate sessions. |
| 2 | Send/receive media with transfer progress | Establish one understandable upload experience that every client can use. |
| 3 | Native iPhone and iPad application | Add the requested Apple devices using the existing session model and the transfer work above. |
| 4 | Everyday usability | Make connecting, selecting destinations and returning to unfinished work easier. |
| 5 | Libraries and additional capabilities | Broaden Eluno around actual usage without making connection setup harder. |

### 1. Linux desktop application

- [ ] Reuse `apps/desktop`, `apps/web`, and `packages/core`; avoid a separate Linux implementation of sessions and streaming.
- [ ] Remove Windows-only icon, directory and executable assumptions from the shared desktop startup/build helpers.
- [ ] Add Linux build commands and packaging configuration for **AppImage and .deb**, initially on x64 Ubuntu/Debian-family desktops. Other distributions and ARM64 are follow-up targets, not a blanket compatibility promise.
- [ ] Add Linux icons, desktop-menu integration, sensible app-data locations and a launch flow that starts the companion automatically.
- [ ] Provide understandable private-network/discovery help and handle Linux desktop/session restrictions without requiring users to disable security protections.
- [ ] Support the same pairing, integrated player, photo viewer, sharing, saving and device-removal controls as Windows.
- [ ] Extend build-artifact naming and release inventory to include Linux packages.

Outcome: someone can install/open Eluno on a Linux desktop and use it as the coordinator or media source for connected mobile devices.

### 2. Send and receive media

- [ ] Add **Send a copy** with a named receiving device, distinct from **Share to view**.
- [ ] Let the receiver approve incoming transfers and select a destination. On computers, use a user-chosen receiving folder; on mobile, use an explicit save/import destination.
- [ ] Show a transfer queue with filename, destination, bytes transferred, progress, completion, cancellation and actionable failure messages.
- [ ] Build on the existing bounded transfer and owner-permission model. Write large media incrementally rather than keeping the entire file in memory.
- [ ] Handle available storage, filename conflicts and incomplete files without overwriting existing content silently.
- [ ] Add retry/resume for interrupted copies, tied to the authorized devices and the same source file. Keep incomplete transfers clearly separate from completed files.
- [ ] Implement Windows ↔ Android and Linux ↔ Android first, then connect the same experience to the Apple client.
- [ ] Keep transfer destinations, file paths and received files out of invitation data and automatic diagnostics.

Outcome: a user can send media to another device, see when it has arrived, and use the received copy after the source disconnects.

### 3. iPhone and iPad application

- [ ] Add `apps/ios` as one native **Swift/SwiftUI** application with layouts for iPhone and iPad. Proposed starting minimum: iOS/iPadOS 16; confirm the final minimum when implementation starts.
- [ ] Reuse protocol versioning, device names, QR invitation verification, certificate pinning, explicit approval and access removal. Do not replace these controls with an unverified embedded website.
- [ ] Add QR scanning and explain camera/local-network access when those capabilities are used.
- [ ] Select individual photos/videos using Apple's system Photos picker and documents using the Files picker. Handle iCloud-backed selections with visible preparation progress and cancellation.
- [ ] Stream selected iPhone/iPad media to Windows or Linux. Use bounded local file reads, staging a selected asset in app-private temporary storage when its provider requires it; show preparation rather than implying immediate access.
- [ ] Receive computer media inside Eluno and support **Save to Files**. Add **Save to Photos** for compatible photos/videos with the necessary user permission and clear completion messages.
- [ ] Connect sender-initiated uploads to the receiver approval/destination flow from milestone 2. An incoming transfer must not silently write into Photos.
- [ ] Include an integrated video player, photo navigation, zoom, rotation handling and useful unsupported-format messages.
- [ ] Make iPad layouts work in landscape, portrait and resizable multitasking windows; use the extra space for the media library and player.
- [ ] Handle common Apple media such as HEIC/HEIF and HEVC explicitly: show compatibility, prepare a compatible representation when supported, or explain the limitation. Sharing the original and converting it must be separate decisions.
- [ ] Explain foreground/background transfer behavior and clean up temporary imports. Do not promise continuous mobile background hosting.
- [ ] Add the Xcode project, configuration and signing instructions. Apple builds/signing need access to macOS/Xcode and the owner's Apple signing setup; no such setup is currently provisioned.

Required directions: Windows ↔ iPhone, Windows ↔ iPad, Linux ↔ iPhone, and Linux ↔ iPad, for both streaming and approved copies. All initially use the same private network and a running desktop coordinator. Mobile-only sessions without a desktop are a separate future capability.

Outcome: iPhone/iPad users can choose media to share, play incoming media inside Eluno, and deliberately receive persistent copies.

### 4. Everyday usability

- [ ] Show a clear device overview: this device, connected devices, available destinations, active sharing and transfers.
- [ ] Add desktop drag-and-drop selection and clear previews before sharing or sending.
- [ ] Offer optional remembered devices/reconnection with identity verification, explicit trust removal and no automatic resharing of old files.
- [ ] Provide meaningful recovery for interrupted transfers, network changes, missing source files and insufficient storage.
- [ ] Preserve playback position where appropriate, and make keyboard, touch and assistive controls consistent across clients.
- [ ] Add a simple update-available flow and keep platform-specific installation instructions in the user guide.

### 5. Later expansion candidates

Choose these individually after the cross-platform sharing/copying experience is implemented:

- [ ] Named libraries, albums, favorites and richer search over explicitly shared content.
- [ ] Share whole selected folders/collections with clear access boundaries.
- [ ] Support selected non-media files through the transfer capability.
- [ ] Share extensions so another app can send selected content into Eluno.
- [ ] Android ↔ iPhone/iPad transfers through an existing desktop coordinator.
- [ ] Mobile-only connections, remote access across networks, synchronization and integrations as separate scoped projects.

Remote access would need a new connection/security model and an operating-cost decision. Cloud accounts, subscriptions and a relay service are not prerequisites for the milestones above.

## Recommended next implementation

**Start with Linux packaging and desktop portability, then implement the transfer queue/receiver flow, then the native Apple application.** This keeps the existing Windows/Android work useful, brings Linux into the same codebase, and gives iPhone/iPad a reusable transfer foundation. Prefer extending the current application over rewriting all clients in another framework.

Keep tasks and implementation in this GitHub repository. Update this checklist as code lands; mark a feature implemented separately from declaring a platform or release validated. Do not turn this roadmap into a claim that all phases are already complete.

## Platform references

The Linux package choices are supported by [electron-builder's Linux configuration](https://www.electron.build/v26/docs/linux/). The Apple selection approach follows [Apple's Photos picker guidance](https://developer.apple.com/videos/play/wwdc2022/10023/), including file-based loading for selected media. These describe platform capabilities; they do not establish that Eluno has implemented them.
