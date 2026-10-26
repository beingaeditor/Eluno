# Eluno feasibility prototype

**Historical Phase 1 notes below.** The active server entry now re-exports `packages/core/server.mjs`; root commands run the current application. Use the [current README](../README.md) and [native device test steps](../docs/phase-1/DEVICE_VALIDATION.md). The old `prototype/public` files are retained as historical source and are not served. The old HTTP LAN description, camera-browser QR flow, 30-minute default, and absence of native packages below describe the earlier experiment, not the current build. Current LAN mode is pinned TLS for native Android, sessions default to eight hours, and the Windows installer starts the service automatically.

Local engineering tool for Phase 1. This is not the finished Eluno web/Android product.

## Developer setup

Requires Node.js 22 or later. From the repository root:

```powershell
npm ci
npm start
```

Open the printed Local URL. The default server listens only on `127.0.0.1`.

For two-client experiments, open two separate tabs. Name both, create a connection in one, enter its code in the other, and approve the request. Use Try with sample media on either side and view it from the other. Keep both tabs open.

Native playback controls require a deliberate click/tap to start video. QR images are generated locally. No account or third-party media service is used.

## LAN experiment

```powershell
npm run start:lan
```

This binds to local network interfaces and exposes the prototype HTTP service. Only generated test media should be used: the transport is not encrypted. The development address selector helps choose the Wi-Fi interface for QR generation; it is not the intended consumer setup.

The phone's ordinary camera can open the QR invitation, which pre-fills the pairing code. Approval is still required. No native Android package, automatic discovery UI, or camera-scanning SDK is included.

Set `ELUNO_PORT` to choose a different port if needed. Stop the server with Ctrl+C when finished.

## Checks

```powershell
npm run check
npm test
npm run probe:discovery
```

The discovery probe runs for at most five seconds and checks DNS-SD PTR/SRV/TXT/A records between two sockets on this computer. It defaults to the loopback interface. Set `ELUNO_DISCOVERY_INTERFACE` to a known interface only for a deliberate LAN experiment. It advertises disposable metadata, never pairing codes or file paths, and does not implement a production discovery service.

## Data path

The browser registers metadata for selected File objects. When another client opens an item, the companion requests its bytes from the source browser in chunks of at most 256 KiB and forwards them to the requesting media element. HTTP Range requests preserve seeking. The companion does not save media to disk.

Both clients implement this source behavior. That permits either direction without requiring a whole-file upload before viewing.

Credentials live in page memory and media access tickets are scoped to a file/session. Unsharing or disconnecting invalidates grants. Content already received by a viewer cannot be recalled.

## Limits

- File objects and device credentials are not restored after a tab reload.
- The session creator leaving ends the session for all participants.
- Codes last five minutes, pending approval requests one minute, and sessions 30 minutes. New codes can be requested during an active session.
- A source must remain available to answer requests. A stalled read times out after 12 seconds; the viewer can retry.
- Local protocol tests do not establish phone locking, background execution, native permissions, real Wi-Fi performance, or codec support on physical Android devices.
- Supported input MIME types: MP4, WebM, JPEG, PNG, and WebP. The decoder may still reject an unsupported codec inside an allowed container.
- No automatic conversion, internet relay, media persistence, native installer, or application-store package is included.
- The source file is user-selected; there is no arbitrary filesystem-path endpoint.

## Optional generated fixtures

`tools/generate-fixtures.py` uses PyAV, NumPy, and Pillow in a development environment to generate original samples. These packages are not application runtime dependencies. Pass `--extra-site-packages` only when intentionally using a trusted existing QA dependency directory.

```powershell
python prototype/tools/generate-fixtures.py
```

Outputs are ignored under `.eluno-local/fixtures`. A normal tester can instead use the built-in sample button with no Python setup.

See [the evidence report](../docs/phase-1/FEASIBILITY_REPORT.md), [architecture decision](../docs/phase-1/ARCHITECTURE_DECISION.md), and [device test handoff](../docs/phase-1/DEVICE_VALIDATION.md).
