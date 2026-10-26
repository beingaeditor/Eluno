# Eluno — Phase 1 feasibility report

Recorded 22 October 2026. Windows + Android is the selected platform priority.

## Verdict

The local engineering prototype, automated protocol suite, browser experiments, research, and provisional architecture decision are delivered. Phase 0 is complete. Phase 1's original real-device gate remains open: the user requested that Android test steps be prepared for later.

No physical Android playback, permission, lock/background, or Wi-Fi compatibility result is claimed. Native clients, automatic discovery in the application, and production encrypted pairing remain future implementation/validation work.

## Delivered

- [Product brief](../phase-0/PRODUCT_BRIEF.md): platform order, first-release scope, success targets, naming, and visual direction.
- [Screen flows](../phase-0/SCREEN_FLOWS.md): onboarding, both sharing directions, permissions, viewing, recovery, and disconnection.
- [Working prototype](../../prototype/README.md): Node companion and responsive browser UI, with integrated video and photo viewers.
- [Architecture decision](ARCHITECTURE_DECISION.md): comparison of browser-only, companion/native, cloud relay, and pre-copy approaches; privacy/cost/format/lifecycle tradeoffs and primary sources.
- [Device test handoff](DEVICE_VALIDATION.md): exact steps, failure cases, native-only checks, and a results table for later physical validation.
- Original generated test media, a reproducible fixture generator, and a disposable DNS-SD discovery probe.

## Automated results

Environment: Windows, Node.js 24.14.0. Socket tests required running outside the execution sandbox; the application remained local. Dependencies are pinned in package-lock.json.

| Check | Result | What it establishes |
| --- | --- | --- |
| Syntax checks | Passed | Server, browser script, discovery script parse successfully |
| Protocol integration suite | 14 passed, 0 failed | Pairing, access, byte transport, expiry, revocation, and recovery contract on loopback |
| Same-computer DNS-SD probe | Passed | PTR/SRV/TXT/A discovery exchange between local multicast sockets; not Android discovery |
| Original H.264/AAC fixture generation | Passed | A five-second MP4 with 120 video frames can be generated and decoded by the QA tooling |

The final integration suite is preserved in [TEST_OUTPUT.tap](TEST_OUTPUT.tap). It covers:

1. Full/open-ended/suffix/invalid byte ranges.
2. Approval-required pairing and access rejection before approval.
3. Decline and cancellation cleanup.
4. Forward and reverse original-byte delivery, seeking, and suffix reads.
5. Photo byte delivery and HEAD without reading source data.
6. A virtual five-GiB file with a seek near its end.
7. Grant revocation and rejection of another device's delete attempt.
8. Revocation during an in-flight read.
9. Leaving and ending sessions.
10. Expiring codes, pending approval requests, and sessions; renewing a code.
11. Pair-code guessing limits.
12. Unsupported content, invalid ranges, forged Host headers, cross-origin requests, and invalid tickets.
13. Source timeout and recovery using the same session.
14. QR PNG generation and rejection of external QR destinations.

## Measured bounds and limits

- The final forward protocol run read 531,942 bytes plus a seek/suffix sequence in 19 ms; the reverse run took 9 ms. These are small loopback protocol observations, not first-frame times or mobile/Wi-Fi throughput promises.
- The largest source read in those runs was 262,144 bytes (256 KiB), matching the chunk cap.
- The virtual five-GiB test requested only the last 8,192 bytes and verified the offset and returned data. It does not prove playback of a real five-GiB video or codec compatibility.
- The discovery probe's first successful loopback run completed in 2 ms without warnings. This does not measure a router or Android discovery stack.
- Whole-process peak memory, sustained 1080p performance, real large-file playback, and battery use were not measured. Bounded source reads are evidence for the approach, not a complete resource profile.

## Browser observations

Two separate Codex in-app browser tabs on the same Windows computer acted as independent clients. The second client was not an Android device.

| Journey | Observed result |
| --- | --- |
| Name devices, create connection, join, approve | Both client names appeared; requester waited for approval |
| First client → second: PNG | Integrated photo viewer loaded a 640 × 360 image |
| First client → second: generated VP8 WebM | Video readyState 4, 640 × 360, about 2.40 seconds; playback advanced with paused=false and no media error |
| Second client → first: PNG | Integrated photo viewer loaded a 640 × 360 image |
| Second client → first: generated VP8 WebM | Video readyState 4, 640 × 360, about 2.41 seconds; playback advanced with paused=false and no media error |
| First client → second: generated H.264/AAC MP4 | Video readyState 4, 640 × 360, five-second duration; native playback advanced without a media error |
| Stop an item while remote photo viewer is open | Viewer closed; item disappeared; receiver showed that sharing ended |
| Responsive widths | At 390px and 800px, document width stayed within the viewport; desktop layout was visually reviewed |
| Browser error log at inspection | No errors or warnings returned |

Byte-range seeking passed at the protocol level. The attempted native scrubber automation did not establish a reliable browser seek result, so interactive seeking remains on the device checklist. Fullscreen, subjective audio quality, JPEG/WebP decoding, orientation changes, and browser background behavior were not separately verified.

Review images: [desktop onboarding](screenshots/desktop-onboarding.jpg), [phone-width shared workspace](screenshots/phone-layout.jpg), and [tablet onboarding](screenshots/tablet-onboarding.jpg). They are responsive desktop-browser screenshots, not screenshots from physical mobile devices.

## Remaining gate

Complete the prepared [hardware matrix](DEVICE_VALIDATION.md) on representative Android phone/tablet hardware and prove native discovery, permission, and encrypted trust-bootstrap behavior before finalizing platform feasibility. The absence of an attached Android device prevents those observations here; the user explicitly chose to perform them later.

The next stage can reuse the prototype's session/range contracts. It must not treat this report as a finished Android app, an encrypted LAN product, or a production performance sign-off.
