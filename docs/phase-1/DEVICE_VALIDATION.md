# Eluno — Windows/Android validation handoff

Hardware validation was deferred by the user on 22 October 2026. Updated 24 October for the native 0.2.0 beta. Phase 1's original real-device completion gate remains open. No Android phone/tablet was attached during the original check; this does not establish which devices the user owns. Build success is not hardware validation.

## Test kit

- A Windows 11 x64 computer with the Eluno beta installer; validate Windows 10 separately before advertising it.
- An Android 12+ phone and, for tablet acceptance, an Android 12+ tablet on the same private Wi-Fi.
- The current Android debug APK for internal testing, or a release APK signed by the chosen beta identity. The unsigned release output cannot be installed as-is.
- Original generated samples, not personal files: `prototype/tools/generate-fixtures.py` produces H.264/AAC MP4, JPEG, PNG, and WebP fixtures in the ignored `.eluno-local/fixtures` directory.
- The in-app Try with sample media button creates a PNG and, where supported, a short WebM video entirely on the device. It requires no camera or microphone access.

The current LAN service uses TLS with a certificate fingerprint carried by the native QR invitation. Use disposable generated samples for acceptance. No browser certificate warning bypass or manual certificate installation should be needed.

## Guided test session

Install the internal beta packages on the QA devices. The person testing should not have to run commands or type an IP address. For development, `npm run desktop` is an alternative to the Windows installer.

1. Open Eluno from Windows Start. If Windows presents a firewall prompt, allow only the intended private-network access; keep the firewall enabled.
2. Name the computer Windows test and Continue. No browser URL should have to be typed.
3. Choose Connect another device and verify a QR invitation is visible.
4. Open the native Eluno Android app. Name it Android test, choose Scan computer invitation, allow the camera when requested, and scan the computer's QR. Confirm Connect.
5. Approve Android test on the computer. Verify both names appear on both screens. Nearby discovery may show the computer; scan verification is still required.
6. On Windows, add the generated MP4 and photos. On Android, play the video, pause, seek to several positions, test audio/fullscreen, and view/zoom/navigate photos.
7. On Android, select downloaded/generated sample files with Add photos or videos. On Windows, view and play those Android-sourced items. Verify playback begins without a separate whole-file copying step.
8. With an item open remotely, choose Stop on its source. Verify the remote viewer closes and the item disappears.
9. Disconnect. Verify the other screen returns to a disconnected state. Old media access must not reopen.
10. Test Allow copies on one item, save it remotely and verify its bytes/content. Disable copies and check the download option disappears while viewing remains available. Remove a peer and verify its media disappears. Close Eluno after testing.

## Failure and lifecycle checks

| Check | Expected product behavior | Result |
| --- | --- | --- |
| Decline pairing | No content access; requester can try again | Pending on Android |
| Expired five-minute code | Clear expired-code recovery; existing approved session remains usable | Pending on Android |
| Isolated guest Wi-Fi / unreachable invitation endpoints | Explain unreachable companion and provide retry guidance | Pending |
| Wi-Fi off during playback, then on | Show interruption; retry succeeds if original session is still valid | Pending |
| Switch to another network | Do not silently trust a new endpoint; require authenticated recovery or pairing | Pending |
| Lock Android source for 60 seconds, then unlock | No promise of continued sharing; source unavailability/retry must be understandable | Pending |
| Switch Android source app to background | Record whether reads continue, pause, or fail; do not generalize from one handset | Pending |
| Close source tab | End its participation; remove its shared items and revoke grants | Pending on Android |
| Reload source tab | Fresh session required; no claim that selected files survive | Pending on Android |
| Rotate during playback/photo viewing | Record position, orientation, zoom, and layout behavior | Pending |
| Unsupported file/codec | Clear recoverable error; source original remains untouched | Pending on Android |
| Actual large video (at least 1 GiB) | Play and seek near beginning/middle/end without pre-copy; monitor memory | Pending |
| Multiple read attempts / repeated seek | No stuck requests, runaway memory, or stale viewer state | Pending on Android |

## Native-only checks before declaring platform feasibility

The native app now implements these paths, but they must be verified on actual devices before the Phase 1 platform decision becomes final:

- Android network service discovery resolves the Windows companion on real Wi-Fi; QR fallback reaches the same authenticated companion.
- Local-network permission prompts, denial, revocation, and restoration follow the selected Android target SDK's rules.
- The system media picker exposes only selected content and preserves the necessary grants for the intended session.
- Encrypted transport and invitation-bound certificate/key verification work without certificate warning bypasses or manual certificate installation.
- Reconnection preserves verified identity; an unrelated device cannot impersonate the old source.
- Any proposed foreground/background service behavior complies with Android's service type and lifecycle rules and is measured on hardware.

## Record each run

Use one row per actual device and direction; do not replace hardware with a desktop browser carrying an Android label.

| Date | Windows build / browser | Android model / OS / Chrome or app build | Direction | Media/container/codec/size | Pair time | First frame | Seek recovery | Lifecycle result | Pass/fail and evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Not run | — | — | Windows → Android | — | — | — | — | — | Pending |
| Not run | — | — | Android → Windows | — | — | — | — | — | Pending |
| Not run | — | Android tablet | Both | — | — | — | — | — | Pending |

## Acceptance

Close the original Phase 1 gate only when representative physical devices pass both media directions and the platform connection/permission checks, with limitations documented. Until then, local protocol/browser results support further implementation but do not establish Android release readiness.
