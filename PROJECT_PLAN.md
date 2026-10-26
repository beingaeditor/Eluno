# Eluno — Phase Plan

Status: updated 24 October 2026 during implementation. Engineering progress is recorded separately from hardware, beta, and distribution acceptance.

Direction update, 27 October 2026: use [FUTURE_TASKS.md](FUTURE_TASKS.md) for the current implementation backlog. The user requested Linux support and uploads to/from iPhone and iPad, and deferred testing work for now. Earlier validation gates below remain recorded rather than marked complete; they are not the current work queue.

| Phase | Current status | Evidence |
| --- | --- | --- |
| 0 — Product definition | Complete; Windows + Android priority selected by the user | [Product brief](docs/phase-0/PRODUCT_BRIEF.md), [screen flows](docs/phase-0/SCREEN_FLOWS.md) |
| 1 — Feasibility | Local prototype, tests, research, and architecture decision delivered; original physical-device gate remains open | [Report](docs/phase-1/FEASIBILITY_REPORT.md), [architecture](docs/phase-1/ARCHITECTURE_DECISION.md) |
| 1 — Android hardware acceptance | Deferred by the user; not passed or represented as complete | [Prepared device steps](docs/phase-1/DEVICE_VALIDATION.md) |
| 2 — Shared foundations | Implemented; source repository selected: [beingaeditor/Eluno](https://github.com/beingaeditor/Eluno) | `packages/core`, `packages/protocol`, `apps/*`, build scripts and CI |
| 3 — Two-way MVP | Implemented; 19 protocol/security integration tests passed; native Android debug build succeeded | Web viewer, Windows shell, Android Media3 player; physical acceptance pending |
| 4 — Beta hardening | Automated checks and troubleshooting implemented; real-user beta and final browser pass pending | Initial Android lint: 0 errors, 15 warnings; prepared device tests retained |
| 5 — Packaging and release | In progress; Windows installer build, Android release build, and documentation being finalized | Internal beta only; production signing, stores, hosting and release acceptance pending |
| 6 — Expansion | Search and owner-authorized save-copy capabilities implemented | Versioned module contracts; remote access, sync and iOS remain future work |

## Product direction

Build an approachable application that works across computers, phones, and tablets. Media sharing is the first capability, with a broader product identity that can support future modules.

The first release should let a nontechnical person pair devices and view selected videos or photos in either direction without managing server commands, IP addresses, or ports.

## Working scope

- Launch target: local-network use; internet streaming is a later decision.
- Clients: a web application plus dedicated phone/tablet applications.
- Content: user-selected photos and videos, viewed inside Eluno.
- Direction: computer to phone/tablet and phone/tablet to computer.
- Privacy: access only to content the person explicitly shares, with visible active sessions and a way to revoke access.
- Setup: guided installation and pairing for any required companion software.
- Brand: Eluno throughout product design and new application code.

Supported operating systems, browser versions, formats, account requirements, and minimum device specifications must be confirmed before committing to a release date. Phase 1 must establish what can run in a browser and what requires an installed application.

## Phase 0 — Define the first product

Deliverables:

- Confirm the first computer operating system and the priority order for iPhone/iPad and Android support.
- Define the three primary journeys: connect devices, share from a computer, and share from a phone/tablet.
- Draft screens for onboarding, device selection, shared content, playback, and connection errors.
- Agree on first-release boundaries, success measures, and the meaning of sharing: live access to selected files versus a separate optional file-copy feature.
- Establish Eluno's initial visual identity and naming conventions.

Completion gate: an agreed first-release brief and screen flow covering both sharing directions, including permissions and disconnection.

## Phase 1 — Prove the difficult device flows

Deliverables:

- Build small disposable prototypes for computer-to-mobile and mobile-to-computer playback on real target devices.
- Verify device discovery, QR/code pairing, local-network permissions, and connection recovery.
- Check browser and app requirements for file selection, streaming, seeking, photo display, and access to large files.
- Test what happens when a phone locks, an app goes into the background, a tab closes, or the network changes. Define supported behavior explicitly.
- Compare direct connections, a computer companion, and any signaling or relay requirements. Document privacy and operating costs for the chosen approach.
- Establish the initial format compatibility list and whether conversion is needed. Show clear behavior for unsupported files.

Completion gate: videos and photos work in both directions on representative hardware, with an evidence-based architecture decision and a documented list of limitations. Do not promise continuous background hosting from mobile devices until it is proven.

## Phase 2 — Establish the codebase and shared foundations

Deliverables:

- Create the GitHub repository when requested, using Eluno naming and the agreed source structure.
- Choose the web, mobile, and companion technology based on Phase 1 results.
- Separate shared session, device, and content contracts from platform-specific file and network access.
- Implement a common design system, navigation, permission explanations, and accessible controls.
- Define secure pairing, session expiry, access revocation, and error handling.
- Add appropriate automated checks, build instructions, and environment configuration without committing secrets.

Completion gate: the initial applications build and run on the agreed target platforms, with a shared pairing/session contract and a repeatable development setup.

## Phase 3 — Build the two-way media MVP

Deliverables:

- Guided setup and pairing, with human-readable device names and useful connection status.
- Selection and sharing of individual files or explicitly permitted collections.
- Built-in video playback: play/pause, seeking, volume, fullscreen, and playback errors.
- Built-in photo viewing: thumbnails, navigation, zoom, and orientation handling.
- Computer-to-phone/tablet and phone/tablet-to-computer sessions using the same understandable workflow.
- Phone/tablet layouts adapted to touch, screen rotation, and available screen space.
- Visible sharing controls, immediate access revocation, and clean session shutdown.

Completion gate: a new user can complete setup, pair devices, play a video, browse photos, reverse the sharing direction, and stop sharing without developer assistance.

## Phase 4 — Run a real-user beta

Deliverables:

- Test first-time setup with nontechnical users and fix the points where they get stuck.
- Validate the supported device/browser matrix, common media formats, and large files.
- Test interrupted connections, permission denial, unavailable devices, concurrent sessions, and unsupported content.
- Measure connection success, time to first playback, seeking reliability, and resource use on representative devices.
- Review privacy, pairing protections, accessibility, and the clarity of recovery instructions.
- Provide understandable help and consent-based diagnostics for troubleshooting.

Completion gate: the agreed supported scenarios are reliable, launch-blocking issues are resolved, and known limitations are visible to users. Set numeric performance targets using Phase 1 measurements before beta starts.

## Phase 5 — Package and release Eluno 1.0

Deliverables:

- Production web hosting and any required connection services with monitoring and an operating-cost budget.
- Signed computer companion installers if required, including a clear update path.
- Phone/tablet release builds and the required store or beta distribution process.
- Setup documentation, privacy policy, support route, release notes, and a tested recovery/rollback process.
- A final check that installation and everyday use require no developer commands or manually entered network addresses.

Completion gate: a user can obtain Eluno through the intended distribution channels and complete the supported end-to-end journeys on each launch platform.

## Phase 6 — Expand the platform

Choose the next capability from observed user needs. Candidate directions include:

- File transfer and downloads.
- Personal libraries, organization, and search.
- Cross-device continuity and synchronization.
- Shared spaces and collaboration.
- Remote access across different networks.
- Integrations and additional content types.

Each addition needs its own short brief, privacy model, prototype, and release gate. Keep optional modules separate from the core device/session model so new capabilities do not complicate the basic experience.

Completion gate for each expansion: evidence of a user need, a defined success measure, and a validated flow that preserves simple onboarding.

## Delivery order and next action

Proceed in phase order. Use Phase 1 evidence to size implementation work and make platform commitments; a calendar estimate before that would be speculative.

Phase 0 is complete. The user requested Android test steps for later, so physical-device validation and native connection/permission proof remain open; the original Phase 1 completion gate has not been waived. Phases 2–3 now have an implemented codebase. Search and explicit saving copies are the first Phase 6 extensions.

Finish packaging and release documentation, then execute the prepared Windows/Android hardware matrix and a nontechnical-user beta. Browser QA was blocked by automatic approval review reporting an account usage limit; do not count that final pass as completed. The user selected https://github.com/beingaeditor/Eluno as the source repository on 27 October 2026; maintain subsequent code changes there. Platform compatibility must not be advertised as proven before the open checks pass.
