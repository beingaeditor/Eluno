# Eluno 0.2 architecture and security

## Runtime structure

The Windows Electron application starts one shared Node service. Its browser UI is served over loopback HTTP on a random port; Electron keeps Node integration off, context isolation on, sandboxing on, denies new windows and permission requests, and restricts top-level navigation to that origin. A strict content security policy and origin/Host validation protect the API from ordinary web-origin access. Session credentials stay in renderer memory; no preload bridge exposes the filesystem.

Android is a native Java application (minimum API 31, target/compile API 36). System document pickers select source files and download destinations. QR scanning uses ZXing. Media3 handles video with an OkHttp data source; Android's image decoder uses a bounded temporary cache file and sampling for photos. NSD discovers the `_eluno._tcp.` service, but connection trust comes from scanning a visible invitation.

The same service exposes a separate LAN HTTPS listener. A per-installation RSA-2048 certificate is self-signed and valid for one year. The QR transfers its SHA-256 fingerprint out of band. Android accepts only canonical private IPv4 HTTPS endpoints and verifies certificate validity plus that exact fingerprint on the TLS connection. Its host verifier also restricts the host to the selected invitation endpoint. Redirects are disabled. No global trust store is modified and no browser security warning is bypassed. IPv6 and public-address invitations are not implemented.

## Pairing and lifecycle

1. The computer registers an in-memory device and creates an eight-hour session.
2. A five-minute invitation carries protocol version, private HTTPS endpoints, a certificate fingerprint and six-digit code.
3. Android tries those endpoints using the pin, registers itself, and requests admission with the code.
4. The creator explicitly approves or declines the displayed name. Pending requests expire after one minute.
5. Each member long-polls events. The sharing device receives requests for bounded byte ranges of its selected files.
6. Stop, removal, expiry and disconnect revoke grants and cancel pending/in-flight reads. Removing a source also removes its shared metadata.

Codes are generated using cryptographic randomness, with per-address rate limits. API bearer tokens and media tickets each use 24 random bytes. Media tickets are bound to a session, file, source, viewer and purpose; they are bearer credentials and must not be logged or shared. Ticket URLs are same-origin, carry no-referrer headers, and are not persisted by application code. Media already delivered is outside revocation's reach.

## Data flow and bounds

Both directions use the same `/media/:id?ticket=…` endpoint. Range/HEAD support permits seeking without loading the whole original. The server asks the source for chunks of at most 256 KiB and writes each chunk with backpressure. Android reads selected content using long offsets; browser sources use `File.slice`. The computer coordinates all streams, so phone-to-computer transfer still depends on that computer being open.

Limits: eight members per session, eight concurrent media responses per session, 50 additions per request, 250 shared items per session, 50 MiB per photo, 200 registered devices and 50 sessions per service. Request bodies and metadata are bounded. No arbitrary filesystem path is accepted by the service. Content type/name/size validation is metadata validation, not malware scanning; the viewer decoder must remain updated.

Android pauses polling in the background and pauses video playback. Foreground sessions request that the screen remain awake. No foreground service, mobile background-hosting promise, direct peer mesh, transcoding, TURN/relay, cloud library or remote internet access is included. Source providers must support random-access local reads. Full-file bytes are not retained by the coordinator, but some buffering is expected in players, operating systems and transports.

## Capabilities and contracts

`packages/protocol/index.d.ts` declares device, media, session, read request, snapshot and invitation types. `index.mjs` declares protocol version 1 and `media`, `search`, `save-copy` capability versions. Server health reports these capabilities. The native client currently uses JSON equivalents; protocol changes require updating both implementations and their contract tests.

Search is client-local over shared metadata. Downloads require `allowDownload: true` set by the item's owner. A separate `download` ticket adds Content-Disposition; disabling download invalidates those grants without removing viewing grants. This is an access convenience, not DRM. These capabilities establish an extension boundary without introducing accounts or remote services.

## Trust boundary and remaining review

The threat model includes accidental oversharing, unapproved LAN clients, stale tickets, hostile web origins, code guessing and QR endpoint redirection. A compromised computer, a malicious approved viewer, OS-level credential theft or a photographed invitation is not solved by transport encryption. App-data ACLs depend on Windows account protections; the identity is not currently hardware-backed. Certificate renewal is explicit: close Eluno, back up app data privately, remove only its identity file, reopen and pair again. Never include that file in reports.

The coordinator is trusted with all session content. Native certificate pinning has integration coverage on Node plus parser/security unit coverage in Android, but requires actual Android TLS/playback acceptance. Independent security review is still a beta gate. Final browser and native UI passes, TalkBack testing, installation/upgrade/uninstall tests and nontechnical-user beta are pending; automated builds do not establish those outcomes.

Reference decisions: [Electron security](https://www.electronjs.org/docs/latest/tutorial/security), [Android NSD](https://developer.android.com/develop/connectivity/wifi/use-nsd), [Media3 ExoPlayer](https://developer.android.com/media/media3/exoplayer), [Android storage access framework](https://developer.android.com/guide/topics/providers/document-provider).
